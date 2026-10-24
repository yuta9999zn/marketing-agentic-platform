require "rails_helper"

RSpec.describe Ai::Workflows::PersonaDraft do
  let(:org) { create(:organization) }
  let(:user) { create(:user) }
  let(:client) { create(:client, organization: org, industry: "Làm đẹp") }
  let(:campaign) { create(:campaign, organization: org, client: client) }

  it "tạo persona draft có schema hợp lệ và ghi nhận brief nguồn" do
    Ai::Workflows::CampaignBrief.call(campaign: campaign, user: user)
    artifact = described_class.call(campaign: campaign, user: user)

    expect(artifact.kind).to eq("persona")
    expect(artifact.ai_generated).to be true
    expect(artifact.ai_metadata["based_on_brief_id"]).to be_present
    expect(artifact.body).to include("Nỗi đau")
  end
end
