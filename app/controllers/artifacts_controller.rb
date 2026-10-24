class ArtifactsController < ApplicationController
  before_action :set_artifact

  def show
    return unless require_role!(:view, subject: @artifact.campaign)
    @versions = @artifact.artifact_versions.order(version: :desc)
    @rounds = @artifact.approval_rounds.order(id: :desc)
    @open_round = @artifact.approval_rounds.pending.order(id: :desc).first
  end

  def edit
    return unless require_role!(:edit, subject: @artifact.campaign)
  end

  def update
    return unless require_role!(:edit, subject: @artifact.campaign)
    if @artifact.approval_status == "archived"
      return redirect_to artifact_path(@artifact), alert: "Artifact đã lưu trữ/archived — không chỉnh sửa được."
    end

    meta = @artifact.ai_metadata.merge("edited_by_human" => true, "human_reviewed" => true,
                                       "edited_at" => Time.current.iso8601, "edited_by" => current_user.id)
    @artifact.new_version!(params[:artifact][:body], ai_generated: @artifact.ai_generated,
                           ai_metadata: meta, user: current_user,
                           extra: artifact_permitted_extra)
    AuditLog.record!(org: current_organization, user: current_user, action: "artifact.edited", subject: @artifact)
    redirect_to artifact_path(@artifact), notice: "Đã lưu phiên bản mới."
  end

  # Gửi duyệt: mở ApprovalRound với reviewers được chỉ định.
  def submit
    return unless require_role!(:edit, subject: @artifact.campaign)
    reviewers = current_organization.users.where(id: Array(params[:reviewer_ids]))
    if reviewers.empty?
      return redirect_to artifact_path(@artifact), alert: "Chọn ít nhất một người duyệt."
    end

    begin
      Approvals::Submit.call(artifact: @artifact, user: current_user, reviewers: reviewers,
                             due_date: params[:due_date].presence, quorum: params[:quorum].presence)
      redirect_to artifact_path(@artifact), notice: "Đã gửi duyệt — chờ quyết định của reviewer."
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to artifact_path(@artifact), alert: e.message
    end
  end

  def withdraw
    return unless require_role!(:edit, subject: @artifact.campaign)
    begin
      @artifact.withdraw!
    rescue ArgumentError => e
      return redirect_to artifact_path(@artifact), alert: e.message
    end
    AuditLog.record!(org: current_organization, user: current_user, action: "artifact.withdrawn", subject: @artifact)
    redirect_to artifact_path(@artifact), notice: "Đã rút về draft."
  end

  def restore_version
    return unless require_role!(:edit, subject: @artifact.campaign)
    @artifact.restore_version!(params[:version_number], user: current_user)
    AuditLog.record!(org: current_organization, user: current_user, action: "artifact.version_restored",
                     subject: @artifact, details: { "version" => params[:version_number] })
    redirect_to artifact_path(@artifact), notice: "Đã khôi phục v#{params[:version_number]} thành version mới."
  end

  def duplicate
    return unless require_role!(:edit, subject: @artifact.campaign)
    copy = @artifact.duplicate!(user: current_user)
    redirect_to artifact_path(copy), notice: "Đã tạo bản sao."
  end

  # Dịch artifact thành bản nháp mới. Adapter offline trả kết quả ngay; model
  # thật chạy trên máy thì đẩy sang job nền (bài dài mất hàng chục giây).
  def translate
    return unless require_role!(:edit, subject: @artifact.campaign)
    target = params[:target_locale].presence || "en"

    unless Ai::Gateway.synchronous?
      status = Ai::Availability.status
      unless status.ready?
        return redirect_to artifact_path(@artifact),
                           alert: t("marketingos.ai.not_ready",
                                    detail: t("marketingos.ai_status.#{status.detail}",
                                              default: t("marketingos.ai_status.unreachable")))
      end

      ArtifactTranslationJob.perform_later(artifact_id: @artifact.id, user_id: current_user.id,
                                           target_locale: target)
      return redirect_to artifact_path(@artifact),
                         notice: t("marketingos.ai.translation_queued", model: status.model)
    end

    artifact = Translations::CreateService.call(source_artifact: @artifact, user: current_user,
                                                target_locale: target)
    redirect_to artifact_path(artifact), notice: t("marketingos.ai.translation_done")
  rescue Providers::AdapterFactory::ExternalNotConfigured => e
    redirect_to artifact_path(@artifact), alert: e.message
  end

  private

  def set_artifact
    @artifact = Artifact.joins(:campaign).where(campaigns: { organization_id: current_organization.id }).find(params[:id])
  end

  def artifact_permitted_extra
    extra = {}
    extra[:locale] = params[:artifact][:locale] if params[:artifact][:locale].present?
    extra[:channel] = params[:artifact][:channel] if params[:artifact][:channel].present?
    extra[:due_date] = params[:artifact][:due_date] if params[:artifact][:due_date].present?
    extra[:source_note] = params[:artifact][:source_note] if params[:artifact][:source_note].present?
    extra
  end
end
