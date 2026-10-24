class CommentsController < ApplicationController
  def create
    campaign = Campaign.in_org(current_organization).find(params[:comment][:campaign_id])
    return unless require_role!(:comment, subject: campaign)

    # Artifact phải thuộc đúng campaign này — không nhận artifact id tự do.
    artifact_id = params[:comment][:artifact_id].presence
    artifact = artifact_id ? campaign.artifacts.find_by(id: artifact_id) : nil
    if artifact_id && artifact.nil?
      return redirect_to campaign_path(campaign), alert: "Artifact không thuộc campaign này."
    end

    campaign.comments.create!(body: params[:comment][:body], user: current_user, artifact: artifact)
    redirect_to campaign_path(campaign, anchor: artifact ? "artifact-#{artifact.id}" : "comments")
  end
end
