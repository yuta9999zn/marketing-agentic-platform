class Campaign < ApplicationRecord
  STATUSES = %w[draft brief research strategy persona content_plan review approved active delivered archived].freeze
  BRIEF_SECTIONS = %w[business_goal product_service audience insight message success_metrics
                      constraints brand_voice required_assets].freeze

  belongs_to :organization
  belongs_to :client
  belongs_to :owner, class_name: "User", optional: true
  has_many :artifacts, dependent: :destroy
  has_many :campaign_collaborators, dependent: :destroy
  has_many :collaborators, through: :campaign_collaborators, source: :user
  has_many :tasks, dependent: :destroy
  has_many :milestones, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :surveys, dependent: :destroy
  has_many :campaign_collaborator_tokens, dependent: :destroy
  has_many :facebook_posts, dependent: :nullify

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :client_belongs_to_same_organization

  before_validation :set_defaults
  before_validation :sync_owner_membership

  scope :in_org, ->(org) { where(organization: org) }

  def accessible_by?(user, role: nil)
    org_role = user.role_in(organization)
    return false if org_role.nil?
    return true if org_role != "client"
    campaign_collaborators.exists?(user: user)
  end

  def artifact_of_kind(kind)
    artifacts.where(kind: kind).order(:id)
  end

  def latest_open_round
    artifacts.joins(:approval_rounds).where(approval_rounds: { status: "pending" })
             .order("approval_rounds.id DESC").first&.approval_rounds&.pending&.first
  end

  LIFECYCLE_STEPS = [
    { key: "brief",    label: "Brief" },
    { key: "strategy", label: "Strategy" },
    { key: "content",  label: "Content & Scripts" },
    { key: "review",   label: "Review" },
    { key: "launch",   label: "Launch" },
    { key: "report",   label: "Report" }
  ].freeze

  def lifecycle_state(step)
    case step
    when "brief"
      artifact_state("brief")
    when "strategy"
      artifact_state("persona")
    when "content"
      artifact_state("content_plan")
    when "review"
      if artifacts.joins(:approval_rounds).where(approval_rounds: { status: "pending" }).exists? || artifacts.where(approval_status: "in_review").exists?
        "in_progress"
      elsif artifacts.where.not(approval_status: "draft").exists? || status == "review" then "completed"
      else "not_started"
      end
    when "launch"
      %w[active delivered archived].include?(status) ? "completed" : (status == "review" ? "ready_for_review" : "not_started")
    when "report"
      %w[delivered archived].include?(status) ? "completed" : "not_started"
    end
  end

  # Progress thật: task hoàn thành; nếu không có task thì theo artifact đã duyệt.
  def progress_percent
    total = tasks.count + milestones.count
    done = tasks.where(status: "done").count + milestones.where(state: "completed").count
    return ((artifacts.where(approval_status: "approved").count.to_f / [artifacts.count, 1].max) * 100).round if total.zero?

    ((done.to_f / total) * 100).round
  end

  private

  def artifact_state(kind)
    list = artifacts.where(kind: kind)
    return "not_started" if list.empty?
    return "completed" if list.exists?(approval_status: "approved")
    return "blocked" if list.exists?(approval_status: "changes_requested") || list.exists?(approval_status: "rejected")
    return "in_progress" if list.exists?(approval_status: "in_review")

    "in_progress" # có draft, chưa gửi duyệt
  end

  def client_belongs_to_same_organization
    errors.add(:client, "phải thuộc cùng organization") if client && client.organization_id != organization_id
  end

  def set_defaults
    self.lifecycle_stage ||= LIFECYCLE_STEPS.first[:key]
  end

  def sync_owner_membership
    # Owner campaign phải là member của org — không nhận user ngoài tenant.
    self.owner = nil if owner && organization && !organization.users.exists?(owner.id)
  end
end
