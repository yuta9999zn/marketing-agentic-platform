# frozen_string_literal: true

module Notifications
  # Tạo notification in-app. Không side-effect ngoài hệ thống.
  class Builder
    def self.notify(user:, org:, kind:, payload: {})
      return if user.nil?
      Notification.create!(user: user, organization: org, kind: kind, payload: payload)
    end

    def self.notify_role(org:, roles:, kind:, payload: {}, except_user: nil)
      org.memberships.where(role: Array(roles)).each do |m|
        next if except_user && m.user_id == except_user.id
        notify(user: m.user, org: org, kind: kind, payload: payload)
      end
    end
  end
end
