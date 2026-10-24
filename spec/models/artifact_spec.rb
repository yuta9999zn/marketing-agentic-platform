require "rails_helper"

RSpec.describe Artifact do
  let(:campaign) { create(:campaign) }
  let(:user) { create(:user) }

  it "tạo snapshot version khi tạo mới" do
    a = create(:artifact, campaign: campaign)
    expect(a.artifact_versions.count).to eq(1)
    expect(a.artifact_versions.first.version).to eq(1)
  end

  it "new_version! tăng version và reset về draft" do
    a = create(:artifact, campaign: campaign, approval_status: "approved")
    a.new_version!("nội dung mới", ai_generated: true, ai_metadata: { "x" => 1 }, user: user)
    expect(a.reload.version).to eq(2)
    expect(a.approval_status).to eq("draft")
    expect(a.artifact_versions.count).to eq(2)
  end

  it "nhãn AI: AI-generated khi chưa có người sửa, AI-assisted khi đã edit" do
    a = create(:artifact, campaign: campaign, ai_generated: true, ai_metadata: {})
    expect(a.ai_label).to eq("AI-generated")
    a.update!(ai_metadata: { "edited_by_human" => true })
    expect(a.ai_label).to eq("AI-assisted")
  end
end
