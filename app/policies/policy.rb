# frozen_string_literal: true

# RBAC trung tâm: view < comment < edit < approve < manage < admin.
# Policy chạy ở controller — không chỉ ẩn nút ở UI.
#
# Hai nhóm role:
# - Internal (owner/admin/manager/strategist/copywriter/designer/
#   project_manager/approver): quyền theo ROLE_CAP trong toàn organization.
# - Campaign-scoped (client, external_reviewer): mọi quyền đến từ
#   CampaignCollaborator.access của CHÍNH campaign đó — không có quyền mặc định.
class Policy
  RANK = { "view" => 0, "comment" => 1, "edit" => 2, "approve" => 3, "manage" => 4, "admin" => 5 }.freeze

  ROLE_CAP = {
    "owner" => 5, "admin" => 5, "manager" => 4, "project_manager" => 3,
    "approver" => 3, "strategist" => 2, "copywriter" => 2, "designer" => 2,
    "client" => 1, "external_reviewer" => 0
  }.freeze

  CAMPAIGN_SCOPED_ROLES = %w[client external_reviewer].freeze

  # Collaborator access → permission granted trên campaign đó.
  ACCESS_CAP = {
    "view" => %w[view],
    "comment" => %w[view comment],
    "approve" => %w[view comment approve]
  }.freeze

  def initialize(user:, org:, role:, subject: nil)
    @user = user
    @org = org
    @role = role
    @subject = subject
  end

  # `subject:` cho phép view/controller ghi đè subject (vd allowed?(:manage, subject: @campaign)).
  def allowed?(permission, subject: :__use_default__)
    return false if @user.nil? || @org.nil? || @role.nil?

    target = subject == :__use_default__ ? @subject : subject
    return campaign_scoped_check(permission, target) if CAMPAIGN_SCOPED_ROLES.include?(@role)

    ROLE_CAP.fetch(@role, -1) >= RANK.fetch(permission.to_s, 99)
  end

  private

  # Client/external_reviewer: quyền hoàn toàn do collaborator access của
  # campaign được mời quyết định. Campaign khác = từ chối toàn bộ.
  def campaign_scoped_check(permission, target)
    return false unless target.is_a?(Campaign)

    collab = target.campaign_collaborators.find_by(user: @user)
    return false if collab.nil?

    ACCESS_CAP.fetch(collab.access, []).include?(permission.to_s)
  end
end
