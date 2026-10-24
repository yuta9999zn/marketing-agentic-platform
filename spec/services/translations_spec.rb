require "rails_helper"

RSpec.describe Translations::CreateService do
  let(:org) { create(:organization) }
  let(:user) { create(:user) }
  let(:campaign) { create(:campaign, organization: org) }
  let(:source) do
    create(:artifact, campaign: campaign, kind: "social_post",
           body: "Chiến dịch mùa hè ra mắt sản phẩm mới của thương hiệu.")
  end

  it "tạo artifact translation offline: glossary dịch + nhãn nháp + metadata nguồn" do
    artifact = described_class.call(source_artifact: source, user: user, target_locale: "en")
    expect(artifact.kind).to eq("translation")
    expect(artifact.locale).to eq("en")
    expect(artifact.body).to include("[Bản dịch nháp vi→en")
    expect(artifact.body).to include("campaign")
    expect(artifact.ai_metadata["source_artifact_id"]).to eq(source.id)
    expect(artifact.ai_generated).to be true
    expect(AiRun.where(workflow: "translation", output_artifact: artifact)).to exist
  end

  it "fake adapter không gọi mạng và tôn trọng glossary custom" do
    adapter = Providers::TranslationFakeAdapter.new
    out = adapter.translate(text: "Sản phẩm mới", source: "vi", target: "en",
                            glossary: { "sản phẩm" => "product" })
    expect(out).to include("product")
  end
end
