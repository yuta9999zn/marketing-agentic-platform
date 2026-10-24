# frozen_string_literal: true

module Facebook
  # Hàng đợi chia sẻ vào hội nhóm (người dùng tự đăng, app nhắc + ghi kết quả).
  # Quyền: xem = nội bộ; lên kế hoạch/đánh dấu/sửa = edit.
  class GroupSharesController < ApplicationController
    before_action -> { require_internal! }
    before_action :set_post, only: %i[create variants]
    before_action :set_share, only: %i[update destroy complete reopen]

    FILTERS = %w[today upcoming done all].freeze

    def index
      @filter = FILTERS.include?(params[:filter]) ? params[:filter] : "today"
      @mine = params[:mine] != "0"
      scope = FacebookGroupShare.in_org(current_organization)
                                .includes(:facebook_group, :assignee, :completed_by,
                                          facebook_post: [ :facebook_page_connection, { image_attachment: :blob } ])
      scope = scope.where(assignee: current_user) if @mine
      day_end = Time.zone.now.end_of_day
      @shares =
        case @filter
        when "today" then scope.pending.where(scheduled_at: ..day_end).chronological
        when "upcoming" then scope.pending.where(scheduled_at: day_end..).chronological
        when "done" then scope.done.order(completed_at: :desc)
        else scope.order(scheduled_at: :desc)
        end.limit(200).to_a
      base = FacebookGroupShare.in_org(current_organization)
      base = base.where(assignee: current_user) if @mine
      @counts = { "today" => base.pending.where(scheduled_at: ..day_end).count,
                  "upcoming" => base.pending.where(scheduled_at: day_end..).count }
      @assignees = FacebookGroupShare.assignable_users(current_organization)
      @groups_count = current_organization.facebook_groups.active.count
    end

    # Lên kế hoạch chia sẻ bài Page đã đăng vào các nhóm đã chọn.
    def create
      return unless require_role!(:edit)

      result = Facebook::GroupShares::Plan.call(
        post: @post, user: current_user, group_ids: params[:group_ids], start_at: params[:start_at],
        spacing_minutes: params[:spacing_minutes].presence || Facebook::GroupShares::Plan::DEFAULT_SPACING,
        assignee_id: params[:assignee_id]
      )
      if params[:ai_variants] == "1" && result.created.any?
        generate_variants(result.created)
        return if performed?
      end
      notice = t("marketingos.facebook_groups.plan.created", count: result.created.size)
      notice += " #{t('marketingos.facebook_groups.plan.skipped_existing', count: result.skipped_existing.size)}" if result.skipped_existing.any?
      redirect_to facebook_post_path(@post, anchor: "group-shares"), notice: notice
    rescue Facebook::StateError, ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to facebook_post_path(@post, anchor: "group-shares"), alert: e.message
    end

    # AI viết lại biến thể cho các lượt còn chờ của bài này.
    def variants
      return unless require_role!(:edit)

      shares = @post.facebook_group_shares.pending.includes(:facebook_group).chronological.to_a
      return redirect_to facebook_post_path(@post, anchor: "group-shares"), alert: t("marketingos.facebook_groups.errors.no_pending") if shares.empty?

      generate_variants(shares)
      redirect_to facebook_post_path(@post, anchor: "group-shares"), notice: t("marketingos.facebook_groups.variants.done") unless performed?
    end

    def update
      return unless require_role!(:edit)

      Facebook::GroupShares::Transitions.update(@share, user: current_user, scheduled_at: params[:scheduled_at],
                                                        assignee_id: params[:assignee_id],
                                                        message: params.key?(:message) ? params[:message] : nil)
      redirect_back_or(notice: t("marketingos.facebook_groups.share.updated"))
    rescue Facebook::StateError, ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_back_or(alert: e.message)
    end

    def complete
      return unless require_role!(:edit)

      Facebook::GroupShares::Transitions.complete(@share, user: current_user, status: params[:status],
                                                          group_post_url: params[:group_post_url], note: params[:note])
      redirect_back_or(notice: t("marketingos.facebook_groups.share.completed.#{@share.status}", group: @share.facebook_group.name))
    rescue Facebook::StateError, ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_back_or(alert: e.message)
    end

    def reopen
      return unless require_role!(:edit)

      Facebook::GroupShares::Transitions.reopen(@share, user: current_user)
      redirect_back_or(notice: t("marketingos.facebook_groups.share.reopened"))
    rescue Facebook::StateError => e
      redirect_back_or(alert: e.message)
    end

    def destroy
      return unless require_role!(:edit)

      Facebook::GroupShares::Transitions.remove(@share, user: current_user)
      redirect_back_or(notice: t("marketingos.facebook_groups.share.removed"))
    rescue Facebook::StateError => e
      redirect_back_or(alert: e.message)
    end

    private

    def set_post
      @post = FacebookPost.in_org(current_organization).find(params[:post_id])
    end

    def set_share
      @share = FacebookGroupShare.in_org(current_organization).find(params[:id])
    end

    # Fake chạy ngay; model thật chạy nền rồi báo qua thông báo.
    def generate_variants(shares)
      if Ai::Gateway.synchronous?
        Ai::Workflows::FacebookGroupVariants.call(shares: shares, user: current_user)
        return
      end

      status = Ai::Availability.status
      unless status.ready?
        redirect_to facebook_post_path(@post, anchor: "group-shares"),
                    alert: t("marketingos.ai.not_ready", detail: t("marketingos.ai_status.#{status.detail}",
                                                                   default: t("marketingos.ai_status.unreachable")))
        return
      end
      FacebookGroupVariantsJob.perform_later(share_ids: shares.map(&:id), user_id: current_user.id)
      redirect_to facebook_post_path(@post, anchor: "group-shares"), notice: t("marketingos.facebook_groups.variants.queued")
    rescue CDFLHarness::Errors::HarnessError, Ai::Gateway::ConsentRequiredError => e
      redirect_to facebook_post_path(@post, anchor: "group-shares"), alert: t("marketingos.facebook_groups.variants.failed", error: e.message)
    end

    # Quay về trang đã bấm (hàng đợi hoặc trang bài), giữ bộ lọc hiện tại.
    def redirect_back_or(flash_hash)
      redirect_back fallback_location: facebook_group_shares_path, **flash_hash
    end
  end
end
