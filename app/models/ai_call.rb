class AiCall < ApplicationRecord
  # Mirror of the harness Audit middleware sink: prompt/output stored as SHA-256
  # hashes only — raw prompts and completions are never persisted here.
  belongs_to :organization
  belongs_to :user, optional: true

  validates :task, :model, :method, :prompt_sha, presence: true
end
