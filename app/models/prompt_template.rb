class PromptTemplate < ApplicationRecord
  # Thư viện prompt chuẩn: người dùng chọn khi tạo nháp AI (ScriptDraft) —
  # instructions được nối vào prompt, version ghi vào AiRun.prompt_template_version.
  CATEGORIES = %w[brief persona content_plan social_post video_script email ad_copy
                  event_run_of_show landing_page storyboard image_prompt translation other].freeze

  belongs_to :organization
  belongs_to :owner, class_name: "User", optional: true

  validates :name, presence: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }

  scope :in_org, ->(org) { where(organization: org) }
  scope :for_category, ->(cat) { where(category: cat) }

  def version_label = "#{name} v#{version}"
end
