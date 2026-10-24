# frozen_string_literal: true

module Approvals
  # Mở vòng duyệt mới cho version hiện tại của artifact.
  # Chỉ mở khi artifact đang draft/changes_requested/rejected (không phải đang duyệt).
  class Submit
    def self.call(artifact:, user:, reviewers:, due_date: nil, quorum: nil)
      raise ArgumentError, "Artifact đang ở trạng thái #{artifact.approval_status} — không thể gửi duyệt" unless %w[draft changes_requested rejected].include?(artifact.approval_status)

      ActiveRecord::Base.transaction do
        artifact.update!(approval_status: "in_review")
        round = artifact.approval_rounds.create!(
          artifact_version: artifact.version, requester: user,
          due_date: due_date, quorum: quorum, status: "pending",
          reviewer_ids: Array(reviewers).map(&:id)
        )
        Array(reviewers).compact.each do |reviewer|
          Notifications::Builder.notify(user: reviewer, org: artifact.campaign.organization,
                                        kind: "review_requested",
                                        payload: { "artifact_id" => artifact.id,
                                                   "round_id" => round.id,
                                                   "title" => artifact.title })
        end
        AuditLog.record!(org: artifact.campaign.organization, user: user,
                         action: "approval.submitted", subject: round,
                         details: { "artifact_version" => artifact.version,
                                    "reviewers" => Array(reviewers).map(&:id) })
        round
      end
    end
  end
end
