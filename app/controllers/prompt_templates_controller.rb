# Thư viện prompt template — chỉ đội nội bộ. Tạo/sửa cần quyền edit,
# xóa cần manage. Mọi bản ghi scope theo organization hiện tại.
class PromptTemplatesController < ApplicationController
  before_action -> { require_internal! && require_role!(:edit) }, only: %i[new create edit update]
  before_action :set_template, only: %i[edit update destroy]

  def new
    @prompt_template = PromptTemplate.new(locale: I18n.locale.to_s)
  end

  def create
    @prompt_template = PromptTemplate.new(template_params.merge(organization: current_organization,
                                                                owner: current_user))
    if @prompt_template.save
      AuditLog.record!(org: current_organization, user: current_user,
                       action: "prompt_template.created", subject: @prompt_template)
      redirect_to templates_path, notice: t("marketingos.prompt_templates.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    # Sửa nội dung → tăng version để AiRun ghi đúng phiên bản prompt đã dùng.
    bump = @prompt_template.instructions != template_params[:instructions].to_s
    if @prompt_template.update(template_params.merge(bump ? { version: @prompt_template.version + 1 } : {}))
      AuditLog.record!(org: current_organization, user: current_user,
                       action: "prompt_template.updated", subject: @prompt_template)
      redirect_to templates_path, notice: t("marketingos.prompt_templates.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    return unless require_internal! && require_role!(:manage)
    @prompt_template.destroy!
    AuditLog.record!(org: current_organization, user: current_user,
                     action: "prompt_template.deleted", subject: @prompt_template)
    redirect_to templates_path, notice: t("marketingos.prompt_templates.deleted")
  end

  private

  def set_template
    @prompt_template = PromptTemplate.in_org(current_organization).find(params[:id])
  end

  def template_params
    params.require(:prompt_template).permit(:name, :category, :instructions, :output_format, :locale, :shared)
  end
end
