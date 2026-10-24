# frozen_string_literal: true

module Campaigns
  # Đóng gói campaign đang chạy thành ProjectTemplate tái sử dụng: milestone,
  # task và artifact được duyệt (làm mẫu nội dung). Ngày tháng lưu dạng
  # offset_days so với start_date để template áp được cho campaign mới bất kỳ.
  class SaveAsTemplate
    def self.call(campaign:, user:, name:, description: nil, include_artifacts: true)
      base = campaign.start_date || campaign.created_at.to_date

      milestones = campaign.milestones.ordered.map do |m|
        { "title" => m.title, "offset_days" => m.due_at ? (m.due_at.to_date - base).to_i : nil }.compact
      end

      tasks = campaign.tasks.order(:due_date, :id).map do |t|
        {
          "title" => t.title, "priority" => t.priority,
          "offset_days" => t.due_date ? (t.due_date - base).to_i : nil,
          "milestone" => t.milestone&.title
        }.compact
      end

      artifacts =
        if include_artifacts
          campaign.artifacts.where(approval_status: "approved", template: false).map do |a|
            { "kind" => a.kind, "title" => a.title, "body" => a.body.to_s, "channel" => a.channel,
              "locale" => a.locale }.compact
          end
        else
          []
        end

      template = campaign.organization.project_templates.create!(
        name: name,
        description: description.presence || campaign.objective.to_s.truncate(200),
        owner: user,
        config: {
          "brief_data" => campaign.brief_data || {},
          "milestones" => milestones,
          "tasks" => tasks,
          "artifacts" => artifacts,
          "source_campaign_id" => campaign.id
        }
      )
      AuditLog.record!(org: campaign.organization, user: user, action: "project_template.created_from_campaign",
                       subject: template, details: { "campaign_id" => campaign.id })
      template
    end
  end
end
