# frozen_string_literal: true

module Ai
  # Next-best-action cho AI Campaign Copilot — suy ra từ dữ liệu thật của
  # campaign, KHÔNG gọi AI provider. CTA dẫn tới flow local (Fake adapter).
  class NextBestAction
    def self.for(campaign)
      new(campaign).call
    end

    def initialize(campaign)
      @campaign = campaign
    end

    def call
      if brief_missing? || brief_rejected?
        action("Tạo brief campaign", "Chưa có brief được duyệt — mọi bước sau đều dựa trên brief.",
               :generate, "brief")
      elsif persona_missing?
        action("Tạo persona mục tiêu", "Brief đã có; persona giúp chuẩn hoá thông điệp và chọn kênh.",
               :generate, "persona")
      elsif content_plan_missing?
        action("Lập content plan", "Có brief + persona rồi — hãy lên kế hoạch nội dung theo tuần.",
               :generate, "content_plan")
      elsif approvals_pending?
        action("Xem hàng chờ duyệt", "#{@campaign.artifacts.where(approval_status: "in_review").count} artifact đang chờ phê duyệt — duyệt sớm để không chặn timeline.", :queue)
      elsif tasks_overdue?
        action("Xử lý task quá hạn", "#{@campaign.tasks.overdue.count} task đã quá hạn — rà blocker và điều phối lại.", :tasks)
      else
        action("Rà soát trước launch", "Không có việc chặn. Kiểm tra checklist deliverable và timeline.",
               :health)
      end
    end

    private

    def brief_missing? = @campaign.artifact_of_kind("brief").empty?
    def brief_rejected? = @campaign.artifact_of_kind("brief").exists?(approval_status: "changes_requested")
    def persona_missing? = @campaign.artifact_of_kind("persona").empty?
    def content_plan_missing? = @campaign.artifact_of_kind("content_plan").empty?
    def approvals_pending? = @campaign.artifacts.where(approval_status: "in_review").exists?
    def tasks_overdue? = @campaign.tasks.overdue.exists?

    def action(title, why, cta, kind = nil)
      { title: title, why: why, cta: cta, kind: kind,
        provider: "local/fake", consent_needed: false }
    end
  end
end
