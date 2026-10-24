# frozen_string_literal: true

module Campaigns
  # Clone cấu hình ProjectTemplate vào campaign MỚI — không mutate template gốc.
  class CreateFromTemplate
    def self.call(org:, user:, template:, client:, name:, start_date: nil)
      ActiveRecord::Base.transaction do
        parsed_start = start_date.present? ? Date.parse(start_date.to_s) : nil
        campaign = org.campaigns.create!(
          client: client, name: name, owner: user, status: "brief",
          start_date: parsed_start, objective: template.description.to_s.truncate(200),
          brief_data: template.config["brief_data"] || {}
        )
        base = parsed_start || Date.current

        Array(template.config["milestones"]).each_with_index do |m, i|
          campaign.milestones.create!(
            title: m["title"], owner: user, position: i,
            due_at: m["offset_days"] ? base + m["offset_days"].days : nil
          )
        end

        Array(template.config["tasks"]).each do |t|
          milestone = campaign.milestones.find_by(title: t["milestone"])
          campaign.tasks.create!(
            title: t["title"], assignee: user, priority: t["priority"] || "medium",
            due_date: t["offset_days"] ? base + t["offset_days"].days : nil,
            milestone: milestone
          )
        end

        # Artifact mẫu clone thành DRAFT — nội dung cũ là điểm khởi đầu, vẫn phải
        # qua vòng duyệt riêng của campaign mới, không kế thừa trạng thái approved.
        Array(template.config["artifacts"]).each do |a|
          campaign.artifacts.create!(
            kind: a["kind"], title: a["title"], body: a["body"],
            channel: a["channel"], locale: a["locale"] || "vi",
            created_by: user, approval_status: "draft",
            source_note: "Sao chép từ template \"#{template.name}\""
          )
        end

        AuditLog.record!(org: org, user: user, action: "campaign.created_from_template",
                         subject: campaign, details: { "template_id" => template.id })
        campaign
      end
    end
  end
end
