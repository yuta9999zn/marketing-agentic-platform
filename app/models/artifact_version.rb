class ArtifactVersion < ApplicationRecord
  belongs_to :artifact
  belongs_to :created_by, class_name: "User", optional: true
end
