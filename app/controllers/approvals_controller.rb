class ApprovalsController < ApplicationController
  # Quyết định duyệt theo ApprovalRound. Chỉ reviewer được chỉ định quyết định;
  # một reviewer một decision — mọi thứ còn lại bị chặn ở service/model.
  def create
    round = ApprovalRound.joins(artifact: :campaign)
                         .where(campaigns: { organization_id: current_organization.id })
                         .find(params[:round_id])
    return unless require_role!(:approve, subject: round.artifact.campaign)

    begin
      Approvals::Decide.call(round: round, user: current_user,
                             decision: params[:decision], note: params[:note].presence)
      redirect_to artifact_path(round.artifact), notice: "Đã ghi nhận quyết định: #{params[:decision]}."
    rescue ArgumentError => e
      redirect_to artifact_path(round.artifact), alert: e.message
    end
  end
end
