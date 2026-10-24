require "rails_helper"

RSpec.describe Ai::Workflows::ContentPlan do
  let(:org) { create(:organization) }
  let(:user) { create(:user) }
  let(:campaign) { create(:campaign, organization: org) }

  it "không có persona thì kế hoạch nêu rõ thiếu dữ liệu thay vì bịa" do
    artifact = described_class.call(campaign: campaign, user: user)
    expect(artifact.body).to include("Cần bổ sung")
  end

  it "có persona thì sinh items theo tuần" do
    Ai::Workflows::CampaignBrief.call(campaign: campaign, user: user)
    Ai::Workflows::PersonaDraft.call(campaign: campaign, user: user)
    artifact = described_class.call(campaign: campaign, user: user)
    expect(artifact.body).to include("Tuần 1")
  end
end
