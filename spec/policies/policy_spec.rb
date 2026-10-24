require "rails_helper"

RSpec.describe Policy do
  let(:org) { create(:organization) }

  def policy_for(role, subject: nil)
    user = create(:user)
    create(:membership, organization: org, user: user, role: role)
    described_class.new(user: user, org: org, role: role, subject: subject)
  end

  describe "thang quyền" do
    it "owner/admin được mọi quyền kể cả admin" do
      expect(policy_for("owner").allowed?(:admin)).to be true
      expect(policy_for("admin").allowed?(:admin)).to be true
    end

    it "strategist được edit nhưng không được approve/manage" do
      p = policy_for("strategist")
      expect(p.allowed?(:edit)).to be true
      expect(p.allowed?(:approve)).to be false
      expect(p.allowed?(:manage)).to be false
    end

    it "approver được approve nhưng không được manage" do
      p = policy_for("approver")
      expect(p.allowed?(:approve)).to be true
      expect(p.allowed?(:manage)).to be false
    end

    it "client không được edit" do
      expect(policy_for("client").allowed?(:edit)).to be false
    end
  end

  describe "cô lập dữ liệu theo campaign cho client" do
    let(:campaign) { create(:campaign, organization: org) }

    it "client chỉ xem campaign được mời" do
      p = policy_for("client", subject: campaign)
      expect(p.allowed?(:view)).to be false

      campaign.campaign_collaborators.create!(user: p.instance_variable_get(:@user), access: "view")
      expect(p.allowed?(:view)).to be true
      expect(p.allowed?(:comment)).to be false
    end

    it "client access=comment được comment nhưng không được edit" do
      p = policy_for("client", subject: campaign)
      campaign.campaign_collaborators.create!(user: p.instance_variable_get(:@user), access: "comment")
      expect(p.allowed?(:comment)).to be true
      expect(p.allowed?(:edit)).to be false
    end
  end
end
