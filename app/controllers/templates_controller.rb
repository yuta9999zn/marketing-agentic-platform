class TemplatesController < ApplicationController
  # Thư viện template của workspace: ProjectTemplate (quy trình campaign),
  # PromptTemplate (prompt chuẩn cho AI draft), artifact được đánh dấu template.
  def index
    return unless require_internal!
    @project_templates = current_organization.project_templates.order(:name)
    @prompt_templates = PromptTemplate.in_org(current_organization).order(:category, :name)
    @artifact_templates = Artifact.templates.joins(:campaign)
                                  .where(campaigns: { organization_id: current_organization.id })
                                  .order(updated_at: :desc)
    @clients = Client.in_org(current_organization).order(:name)
  end
end
