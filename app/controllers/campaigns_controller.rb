class CampaignsController < ApplicationController
  before_action :set_campaign, only: %i[show edit update generate create_image_prompt set_lifecycle
                                        save_as_template]

  def index
    base = Access::CampaignAccessScope.call(user: current_user, org: current_organization, role: current_role)
    @campaigns = base.includes(:client).order(created_at: :desc).distinct
  end

  def show
    return unless require_role!(:view, subject: @campaign)
    @artifacts = @campaign.artifacts.order(:kind, :id)
    @task_filter = params[:filter].presence
    @tasks = filtered_tasks
    @milestones = @campaign.milestones.ordered
    @events = @campaign.events.order(:starts_at)
    @comment = Comment.new(campaign: @campaign)
    @comments = @campaign.comments.where(artifact_id: nil).order(created_at: :asc)
    @prompt_templates = PromptTemplate.in_org(current_organization).order(:category, :name)
    @surveys = @campaign.surveys.order(created_at: :desc)
  end

  def new
    return unless require_role!(:manage)
    @campaign = Campaign.new
    @clients = Client.in_org(current_organization)
    @project_templates = current_organization.project_templates.order(:name)
  end

  # Wizard một trang cho người không chuyên: đặt tên → AI nháp brief → xem thiếu gì.
  def create
    return unless require_role!(:manage)
    @clients = Client.in_org(current_organization)
    @project_templates = current_organization.project_templates.order(:name)
    @campaign = Campaign.new(campaign_params.merge(organization: current_organization, status: "brief",
                                                   owner: current_user))
    if @campaign.save
      AuditLog.record!(org: current_organization, user: current_user, action: "campaign.created", subject: @campaign)
      redirect_to campaign_path(@campaign), notice: "Đã tạo campaign. Bước tiếp theo: tạo bản nháp brief bằng AI."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    return unless require_role!(:manage, subject: @campaign)
    @clients = Client.in_org(current_organization)
  end

  def update
    return unless require_role!(:manage, subject: @campaign)
    if @campaign.update(campaign_params)
      AuditLog.record!(org: current_organization, user: current_user, action: "campaign.updated", subject: @campaign)
      redirect_to campaign_path(@campaign), notice: "Đã cập nhật."
    else
      @clients = Client.in_org(current_organization)
      render :edit, status: :unprocessable_entity
    end
  end

  # Endpoint AI: luôn tạo DRAFT có nhãn AI-generated; consent_external phải được
  # chủ workspace xác nhận rõ ràng từng lần gọi mới cho phép gửi ra ngoài.
  # Tạo bản nháp bằng AI. Provider nhanh (fake) chạy ngay trong request; model
  # thật chạy trên máy mất 20-90 giây nên đẩy sang job nền — người dùng nhận
  # thông báo khi nháp sẵn sàng thay vì ngồi nhìn trang treo.
  def generate
    return unless require_role!(:edit, subject: @campaign)
    kind = params[:kind]
    return redirect_to campaign_path(@campaign), alert: t("marketingos.ai.bad_kind") unless valid_kind?(kind)

    unless Ai::Gateway.synchronous?
      status = Ai::Availability.status
      unless status.ready?
        return redirect_to campaign_path(@campaign),
                           alert: t("marketingos.ai.not_ready",
                                    detail: t("marketingos.ai_status.#{status.detail}",
                                              default: t("marketingos.ai_status.unreachable")))
      end

      AiDraftJob.perform_later(kind: kind, campaign_id: @campaign.id, user_id: current_user.id,
                               channel: params[:channel].presence,
                               prompt_template_id: params[:prompt_template_id].presence)
      return redirect_to campaign_path(@campaign, anchor: "stage-content"),
                         notice: t("marketingos.ai.queued", model: status.model)
    end

    artifact = generate_now(kind)
    Notifications::Builder.notify_role(org: current_organization, roles: %w[manager approver],
                                       kind: "ai_draft_created",
                                       payload: { "campaign" => @campaign.name, "kind" => kind },
                                       except_user: current_user)
    redirect_to campaign_path(@campaign, anchor: "artifact-#{artifact.id}"),
                notice: t("marketingos.ai.drafted", kind: kind)
  rescue Ai::Gateway::ConsentRequiredError => e
    redirect_to campaign_path(@campaign), alert: e.message
  rescue CDFLHarness::Errors::Error => e
    redirect_to campaign_path(@campaign), alert: t("marketingos.ai.declined", detail: e.message)
  end

  # Tạo campaign từ ProjectTemplate — clone cấu hình, không mutate template.
  def create_from_template
    return unless require_role!(:manage)
    template = current_organization.project_templates.find_by(id: params[:template_id])
    client = current_organization.clients.find_by(id: params[:client_id])
    if template.nil? || client.nil?
      return redirect_to new_campaign_path, alert: "Cần chọn template và client hợp lệ."
    end

    campaign = Campaigns::CreateFromTemplate.call(
      org: current_organization, user: current_user, template: template, client: client,
      name: params[:name].presence || "#{template.name} — #{client.name}",
      start_date: params[:start_date].presence
    )
    redirect_to campaign_path(campaign), notice: "Đã tạo campaign từ template \"#{template.name}\"."
  end

  # Đóng gói campaign hiện tại thành ProjectTemplate tái sử dụng.
  def save_as_template
    return unless require_internal! && require_role!(:manage, subject: @campaign)
    template = Campaigns::SaveAsTemplate.call(
      campaign: @campaign, user: current_user,
      name: params[:name].presence || "#{@campaign.name} (template)",
      description: params[:description].presence,
      include_artifacts: params[:include_artifacts] != "0"
    )
    redirect_to templates_path, notice: t("marketingos.templates.saved_as_template", name: template.name)
  end

  # Image studio: soạn gói prompt ảnh. Với model chạy trên máy, riêng bước này
  # mất khoảng 50 giây nên đẩy sang job nền như các tác vụ AI khác.
  def create_image_prompt
    return unless require_role!(:edit, subject: @campaign)
    opts = image_prompt_options

    unless Ai::Gateway.synchronous?
      status = Ai::Availability.status
      unless status.ready?
        return redirect_to campaign_path(@campaign),
                           alert: t("marketingos.ai.not_ready",
                                    detail: t("marketingos.ai_status.#{status.detail}",
                                              default: t("marketingos.ai_status.unreachable")))
      end

      ImagePromptJob.perform_later(campaign_id: @campaign.id, user_id: current_user.id, options: opts)
      return redirect_to campaign_path(@campaign), notice: t("marketingos.ai.image_queued", model: status.model)
    end

    artifact = Images::CreatePromptService.call(campaign: @campaign, user: current_user, **opts)
    redirect_to artifact_path(artifact), notice: t("marketingos.ai.image_done")
  rescue Providers::AdapterFactory::ExternalNotConfigured => e
    redirect_to campaign_path(@campaign), alert: e.message
  end

  # Đổi lifecycle stage (Brief → ... → Report) — validate stage + manage permission + audit.
  def set_lifecycle
    return unless require_role!(:manage, subject: @campaign)
    stage = params[:stage]
    unless Campaign::LIFECYCLE_STEPS.map { |s| s[:key] }.include?(stage)
      return redirect_to campaign_path(@campaign), alert: "Giai đoạn không hợp lệ."
    end

    @campaign.update!(lifecycle_stage: stage)
    AuditLog.record!(org: current_organization, user: current_user, action: "campaign.lifecycle_changed",
                     subject: @campaign, details: { "stage" => stage })
    redirect_to campaign_path(@campaign, stage: %w[brief strategy content].include?(stage) ? stage : nil),
                notice: "Đã chuyển giai đoạn: #{stage}."
  end

  private

  GENERATABLE_KINDS = (%w[brief persona content_plan] + Ai::Workflows::ScriptDraft::SCRIPT_KINDS).freeze

  def image_prompt_options
    { brand: params[:brand].presence || @campaign.client.name,
      objective: params[:objective].presence || @campaign.objective.to_s,
      audience: params[:audience].presence || @campaign.audience.to_s,
      channel: params[:channel].presence,
      dimensions: params[:dimensions].presence || "1080x1080",
      style: params[:style].presence || "brand-consistent",
      exclusions: params[:exclusions].to_s }
  end

  def valid_kind?(kind) = GENERATABLE_KINDS.include?(kind.to_s)

  def generate_now(kind)
    case kind
    when "brief" then Ai::Workflows::CampaignBrief.call(campaign: @campaign, user: current_user, consent_external: consent_param)
    when "persona" then Ai::Workflows::PersonaDraft.call(campaign: @campaign, user: current_user, consent_external: consent_param)
    when "content_plan" then Ai::Workflows::ContentPlan.call(campaign: @campaign, user: current_user, consent_external: consent_param)
    else
      # prompt_template resolve trong org — id lạ/cross-tenant rơi về nil.
      template = PromptTemplate.in_org(current_organization).find_by(id: params[:prompt_template_id])
      Ai::Workflows::ScriptDraft.call(campaign: @campaign, user: current_user, kind: kind,
                                      channel: params[:channel].presence, prompt_template: template)
    end
  end

  # Client luôn resolve trong org hiện tại — chặn cross-tenant client_id qua HTTP.
  def campaign_params
    permitted = params.require(:campaign).permit(:client_id, :name, :objective, :audience, :channels,
                                                 :budget, :owner_id, :start_date, :end_date,
                                                 brief_data: Campaign::BRIEF_SECTIONS)
    if permitted[:client_id].present?
      permitted[:client_id] = current_organization.clients.find_by(id: permitted[:client_id])&.id
    end
    if permitted[:owner_id].present?
      permitted[:owner_id] = current_organization.users.find_by(id: permitted[:owner_id])&.id
    end
    permitted
  end

  def set_campaign
    @campaign = Campaign.in_org(current_organization).find(params[:id])
  end

  def consent_param
    params[:consent_external] == "true" && ENV["AI_EXTERNAL_ENABLED"] == "true"
  end

  # Filter task theo query param — mọi filter đều là scope thật trên dữ liệu org.
  def filtered_tasks
    scope = @campaign.tasks
    case @task_filter
    when "mine" then scope.where(assignee: current_user)
    when "overdue" then scope.overdue
    when "blocked" then scope.where.not(blocked_reason: nil).where.not(status: "done")
    when "waiting" then scope.waiting_feedback
    else scope
    end.order(:due_date)
  end
end
