# frozen_string_literal: true

module ArtifactsHelper
  KIND_VI = {
    "brief" => "Brief",
    "persona" => "Persona",
    "content_plan" => "Content plan",
    "deliverable" => "Deliverable",
    "image_prompt" => "Image prompt"
  }.freeze

  def kind_label(kind)
    KIND_VI.fetch(kind, kind.humanize)
  end
end
