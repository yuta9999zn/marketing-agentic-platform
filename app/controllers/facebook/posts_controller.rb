# frozen_string_literal: true

module Facebook
  # Bài đăng Facebook: nháp (thủ công/AI) → duyệt → lên lịch → đăng tự động.
  # Quyền: xem = nội bộ; tạo/sửa/lên lịch = edit; duyệt/từ chối = approve.
  class PostsController < ApplicationController
    before_action -> { require_internal! }
    before_action :set_connection
    before_action :set_post, only: %i[show edit update destroy submit approve reject schedule unschedule publish_now cancel retry reopen]

    def index
      scope = FacebookPost.in_org(current_organization).includes(:facebook_page_connection, :created_by, :campaign)
      @filter = params[:filter].presence || "all"
      @posts =
        case @filter
        when "pending" then scope.awaiting_approval.order(submitted_at: :desc)
        when "scheduled" then scope.where(status: "scheduled").order(:scheduled_at)
        when "published" then scope.where(status: "published").order(published_at: :desc)
        when "failed" then scope.where(status: "failed").order(updated_at: :desc)
        when "drafts" then scope.where(status: %w[draft approved cancelled]).order(updated_at: :desc)
        else scope.order(updated_at: :desc)
        end.limit(100)
      @counts = FacebookPost.in_org(current_organization).group(:status).count
      @recent_attempts = FacebookPublishAttempt.joins(:facebook_post)
                                               .where(facebook_posts: { organization_id: current_organization.id })
                                               .includes(:facebook_post).recent.limit(12)
    end

    def show
      @attempts = @post.facebook_publish_attempts.recent
      @audit = AuditLog.where(organization: current_organization, subject_type: "FacebookPost", subject_id: @post.id)
                       .includes(:user).order(created_at: :desc).limit(30)
      @timezones = timezone_options
      @group_shares = @post.facebook_group_shares.includes(:facebook_group, :assignee, :completed_by).chronological.to_a
      @groups = current_organization.facebook_groups.active.ordered.to_a
      @assignees = FacebookGroupShare.assignable_users(current_organization)
    end

    def new
      return unless require_role!(:edit)
      return redirect_to facebook_connection_path, alert: t("marketingos.facebook.posts.need_connection") if @connection.nil?

      @post = FacebookPost.new(timezone: Time.zone.name, post_type: "text")
      @campaigns = current_organization.campaigns.order(:name)
      @artifacts = Artifact.joins(:campaign).where(campaigns: { organization_id: current_organization.id })
                           .where(kind: %w[social_post ad_copy content_plan]).order(updated_at: :desc).limit(50)
      @timezones = timezone_options
    end

    def create
      return unless require_role!(:edit)
      return redirect_to facebook_connection_path, alert: t("marketingos.facebook.posts.need_connection") if @connection.nil?

      post = Facebook::Posts::Compose.call(org: current_organization, connection: @connection, user: current_user,
                                           attrs: post_params.to_h.symbolize_keys, image: params.dig(:post, :image))
      redirect_to facebook_post_path(post), notice: t("marketingos.facebook.posts.created")
    rescue ActiveRecord::RecordInvalid, ArgumentError => e
      redirect_to new_facebook_post_path, alert: e.message
    end

    # AI sinh nháp. Provider fake chạy ngay; model thật chạy nền + thông báo.
    def generate
      return unless require_role!(:edit)
      return redirect_to facebook_connection_path, alert: t("marketingos.facebook.posts.need_connection") if @connection.nil?

      brief = params[:brief].to_s.strip
      return redirect_to new_facebook_post_path, alert: t("marketingos.facebook.posts.brief_required") if brief.blank?

      campaign = current_organization.campaigns.find_by(id: params[:campaign_id])
      artifact = campaign&.artifacts&.find_by(id: params[:artifact_id])
      if Ai::Gateway.synchronous?
        post = Ai::Workflows::FacebookPostDraft.call(connection: @connection, user: current_user, brief: brief,
                                                     campaign: campaign, tone: params[:tone].presence,
                                                     goal: params[:goal].presence, artifact: artifact)
        redirect_to facebook_post_path(post), notice: t("marketingos.facebook.posts.ai_ready")
      else
        status = Ai::Availability.status
        unless status.ready?
          return redirect_to new_facebook_post_path,
                             alert: t("marketingos.ai.not_ready", detail: t("marketingos.ai_status.#{status.detail}",
                                                                           default: t("marketingos.ai_status.unreachable")))
        end
        FacebookPostDraftJob.perform_later(connection_id: @connection.id, user_id: current_user.id, brief: brief,
                                           campaign_id: campaign&.id, tone: params[:tone].presence,
                                           goal: params[:goal].presence, artifact_id: artifact&.id)
        redirect_to facebook_posts_path, notice: t("marketingos.facebook.posts.ai_queued")
      end
    rescue CDFLHarness::Errors::HarnessError, Ai::Gateway::ConsentRequiredError => e
      redirect_to new_facebook_post_path, alert: t("marketingos.facebook.posts.ai_failed", error: e.message)
    end

    def edit
      return unless require_role!(:edit)
      return redirect_to facebook_post_path(@post), alert: t("marketingos.facebook.posts.not_editable") unless @post.editable?

      @timezones = timezone_options
    end

    def update
      return unless require_role!(:edit)

      Facebook::Posts::Transitions.update_content(@post, user: current_user, attrs: post_params.to_h.symbolize_keys,
                                                  image: params.dig(:post, :image), remove_image: params[:remove_image] == "1")
      redirect_to facebook_post_path(@post), notice: t("marketingos.facebook.posts.updated")
    rescue Facebook::StateError, ActiveRecord::RecordInvalid, ArgumentError => e
      redirect_to edit_facebook_post_path(@post), alert: e.message
    end

    def destroy
      return unless require_role!(:manage)
      return redirect_to facebook_post_path(@post), alert: t("marketingos.facebook.posts.cannot_delete") unless %w[draft cancelled].include?(@post.status)

      Facebook::Posts::Audit.record(@post, "deleted", user: current_user)
      @post.destroy
      redirect_to facebook_posts_path, notice: t("marketingos.facebook.posts.deleted")
    end

    def submit
      return unless require_role!(:edit)

      transition(:submit) { Facebook::Posts::Transitions.submit(@post, user: current_user) }
    end

    def approve
      return unless require_role!(:approve)

      transition(:approve) { Facebook::Posts::Transitions.approve(@post, user: current_user, note: params[:note].presence) }
    end

    def reject
      return unless require_role!(:approve)

      transition(:reject) { Facebook::Posts::Transitions.reject(@post, user: current_user, note: params[:note].to_s) }
    end

    def schedule
      return unless require_role!(:edit)

      tz = params[:timezone].presence || @post.timezone
      transition(:schedule) { Facebook::Posts::Transitions.schedule(@post, user: current_user, at: params[:scheduled_at], timezone: tz) }
    end

    def unschedule
      return unless require_role!(:edit)

      transition(:unschedule) { Facebook::Posts::Transitions.unschedule(@post, user: current_user) }
    end

    def publish_now
      return unless require_role!(:edit)

      transition(:publish_now) do
        Facebook::Posts::Transitions.schedule(@post, user: current_user, at: Time.current, timezone: @post.timezone, publish_now: true)
      end
    end

    def cancel
      return unless require_role!(:edit)

      transition(:cancel) { Facebook::Posts::Transitions.cancel(@post, user: current_user, note: params[:note].presence) }
    end

    def retry
      return unless require_role!(:edit)

      transition(:retry) { Facebook::Posts::Transitions.retry(@post, user: current_user, confirm_unknown: params[:confirm] == "1") }
    end

    def reopen
      return unless require_role!(:edit)

      transition(:reopen) { Facebook::Posts::Transitions.reopen(@post, user: current_user) }
    end

    private

    def transition(action)
      yield
      redirect_to facebook_post_path(@post), notice: t("marketingos.facebook.posts.flash.#{action}")
    rescue Facebook::StateError, Facebook::ValidationError, ActiveRecord::RecordInvalid, ArgumentError => e
      message = e.is_a?(Facebook::ValidationError) ? e.issues.map { |i| t("marketingos.facebook.issues.#{i}", default: i.to_s) }.join("; ") : e.message
      redirect_to facebook_post_path(@post), alert: message
    end

    def set_connection
      @connection = current_organization.facebook_page_connections.active.order(updated_at: :desc).first
    end

    def set_post
      @post = FacebookPost.in_org(current_organization).find(params[:id])
    end

    def post_params
      params.fetch(:post, {}).permit(:title, :message, :link, :post_type, :scheduled_at, :timezone, :campaign_id, :artifact_id)
    end

    def timezone_options
      %w[Asia/Ho_Chi_Minh Asia/Bangkok Asia/Singapore Asia/Tokyo Asia/Seoul Australia/Sydney Europe/London
         Europe/Berlin Europe/Paris America/New_York America/Chicago America/Los_Angeles UTC].uniq
    end
  end
end
