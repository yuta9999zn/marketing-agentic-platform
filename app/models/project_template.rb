class ProjectTemplate < ApplicationRecord
  belongs_to :organization
  belongs_to :owner, class_name: "User", optional: true

  validates :name, presence: true

  # Config hiện được clone khi tạo campaign (xem Campaigns::CreateFromTemplate):
  #   milestones: [{title, offset_days}], tasks: [{title, milestone, priority, offset_days}],
  #   brief_data: {}
  # LƯU Ý: key "artifact_kinds" CHƯA được clone — artifact do editor/AI tạo trong
  # campaign, template không sinh artifact rỗng. Đừng claim khác đi trong docs.
end
