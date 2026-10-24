class ContentStudioController < ApplicationController
  def index
    return unless require_internal!
    base = Artifact.joins(:campaign).where(campaigns: { organization_id: current_organization.id })
    @artifacts = base.includes(:campaign, :created_by).order(updated_at: :desc)
    @pending_count = base.where(approval_status: "in_review").count
  end
end
