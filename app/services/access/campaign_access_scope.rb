# frozen_string_literal: true

module Access
  # Scope campaign hợp lệ duy nhất cho mọi query nghiệp vụ:
  # - internal roles: campaign trong current organization;
  # - client/external_reviewer: CHỈ campaign có collaborator của user.
  # Mọi query dashboard/activity/task/event/approval PHẢI bắt đầu từ đây.
  class CampaignAccessScope
    def self.call(user:, org:, role:)
      base = Campaign.where(organization: org)
      return base unless Policy::CAMPAIGN_SCOPED_ROLES.include?(role.to_s)

      base.joins(:campaign_collaborators).where(campaign_collaborators: { user_id: user.id })
    end

    # Sub-select dùng cho where(campaign_id: ...).
    def self.ids_for(user:, org:, role:)
      call(user: user, org: org, role: role).select(:id)
    end
  end
end
