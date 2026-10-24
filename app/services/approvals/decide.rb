# frozen_string_literal: true

module Approvals
  # Reviewer ra quyết định trên round đang mở. Một reviewer — một decision.
  # CHỈ reviewer được chỉ định mới quyết định. Artifact status được
  # ApprovalRound#sync_artifact_status đồng bộ, không ghi đè tự do.
  class Decide
    def self.call(round:, user:, decision:, note: nil)
      round.with_lock do
        round.reload
        artifact = round.artifact

        unless round.status == "pending"
          raise ArgumentError, "Vòng duyệt đã kết thúc (#{round.status})"
        end
        unless Array(round.reviewer_ids).include?(user.id)
          raise ArgumentError, "Bạn không được chỉ định là reviewer cho vòng duyệt này"
        end
        if round.approval_decisions.exists?(user: user)
          raise ArgumentError, "Bạn đã có quyết định cho vòng duyệt này"
        end
        # Version integrity: round phải là của version ĐANG được duyệt.
        if round.artifact_version != artifact.version
          raise ArgumentError, "Vòng duyệt thuộc version cũ (v#{round.artifact_version}) — artifact đã ở v#{artifact.version}"
        end
        unless artifact.approval_status == "in_review"
          raise ArgumentError, "Artifact không còn ở trạng thái chờ duyệt (#{artifact.approval_status})"
        end

        round.decide!(user: user, decision: decision, note: note)
        Notifications::Builder.notify(user: round.requester, org: artifact.campaign.organization,
                                      kind: "approval_decided",
                                      payload: { "artifact_id" => artifact.id,
                                                 "decision" => decision,
                                                 "by" => user.id })
        AuditLog.record!(org: artifact.campaign.organization, user: user,
                         action: "approval.decided.#{decision}", subject: round,
                         details: { "note" => note, "artifact_version" => round.artifact_version })
        round
      end
    end
  end
end
