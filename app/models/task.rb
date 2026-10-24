class Task < ApplicationRecord
  STATUSES = %w[open in_progress done].freeze
  PRIORITIES = %w[low medium high urgent].freeze

  belongs_to :campaign
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :milestone, optional: true
  belongs_to :depends_on, class_name: "Task", optional: true

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :priority, inclusion: { in: PRIORITIES }, allow_nil: true
  validate :assignee_in_campaign_organization
  validate :dependency_in_same_campaign
  validate :milestone_in_same_campaign
  validate :no_dependency_cycle

  scope :waiting_feedback, -> { where.not(blocked_reason: nil).where.not(status: "done") }

  scope :overdue, -> { where.not(status: "done").where("due_date < ?", Date.current) }
  scope :open, -> { where.not(status: "done") }

  def overdue? = !done? && due_date.present? && due_date < Date.current
  def done? = status == "done"

  private

  # Assignee phải là member của organization sở hữu campaign — chặn ở cả model,
  # không chỉ controller.
  def assignee_in_campaign_organization
    return if assignee.nil? || campaign.nil?
    return if campaign.organization.users.exists?(assignee.id)

    errors.add(:assignee, "phải là thành viên của organization")
  end

  def dependency_in_same_campaign
    return if depends_on_id.nil? || campaign.nil?
    return if campaign.tasks.exists?(depends_on_id)

    errors.add(:depends_on, "phải là task trong cùng campaign")
  end

  def milestone_in_same_campaign
    return if milestone.nil? || campaign.nil? || milestone.campaign_id == campaign_id

    errors.add(:milestone, "phải thuộc cùng campaign")
  end

  # Chặn self-dependency và chu trình A→B→A.
  def no_dependency_cycle
    return if depends_on_id.nil?

    if depends_on_id == id
      errors.add(:depends_on, "task không thể phụ thuộc chính nó")
      return
    end

    seen = Set.new([id])
    current = depends_on
    while current
      if seen.include?(current.id)
        errors.add(:depends_on, "tạo chu trình phụ thuộc")
        return
      end
      seen.add(current.id)
      current = current.depends_on
    end
  end
end
