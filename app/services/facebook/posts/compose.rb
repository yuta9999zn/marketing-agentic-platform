# frozen_string_literal: true

module Facebook
  module Posts
    # Tạo bản nháp thủ công hoặc từ nội dung đã có (artifact). Luôn là draft.
    class Compose
      PERMITTED = %i[title message link post_type scheduled_at timezone campaign_id artifact_id].freeze

      def self.call(org:, connection:, user:, attrs:, image: nil)
        post = FacebookPost.new(attrs.slice(*PERMITTED))
        post.organization = org
        post.facebook_page_connection = connection
        post.created_by = user
        post.status = "draft"
        post.timezone = attrs[:timezone].presence || Time.zone.name
        post.scheduled_at = Scheduling.parse_local(attrs[:scheduled_at], post.timezone) if attrs[:scheduled_at].present?
        post.campaign = org.campaigns.find_by(id: attrs[:campaign_id]) if attrs[:campaign_id].present?
        if attrs[:artifact_id].present?
          artifact = Artifact.joins(:campaign).where(campaigns: { organization_id: org.id }).find_by(id: attrs[:artifact_id])
          post.artifact = artifact
          post.message = artifact.body if post.message.blank? && artifact
          post.campaign ||= artifact&.campaign
        end
        post.image.attach(image) if image.present?
        post.post_type = "photo" if post.image.attached? && post.post_type == "text"
        post.save!
        Audit.record(post, "created", user: user, details: { "post_type" => post.post_type })
        post
      end
    end
  end
end
