require "rails_helper"

RSpec.describe Ai::Workflows::CampaignBrief do
  let(:org) { create(:organization) }
  let(:user) { create(:user) }
  let(:client) { create(:client, organization: org, industry: "F&B") }
  let(:campaign) { create(:campaign, organization: org, client: client, objective: nil, start_date: nil, end_date: nil) }

  it "tạo artifact brief dạng draft, gắn nhãn AI + metadata nguồn gốc, và khai báo thiếu dữ liệu" do
    artifact = described_class.call(campaign: campaign, user: user)

    expect(artifact).to be_persisted
    expect(artifact.kind).to eq("brief")
    expect(artifact.ai_generated).to be true
    expect(artifact.approval_status).to eq("draft")
    expect(artifact.ai_metadata["human_reviewed"]).to be false
    expect(artifact.ai_metadata["provider"]).to eq("fake")
    expect(artifact.ai_metadata["missing_data"]).to include("Chưa có mục tiêu định lượng (KPI)")
    expect(AiCall.last).to be_present
    expect(AuditLog.last.action).to eq("ai.brief.drafted")
  end
end
