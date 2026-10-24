require "rails_helper"

RSpec.describe Campaigns::CreateFromTemplate do
  let(:org) { create(:organization) }
  let(:user) { create(:user) }
  let!(:membership) { create(:membership, organization: org, user: user, role: "manager") }
  let(:client) { create(:client, organization: org) }

  let(:template) do
    ProjectTemplate.create!(organization: org, name: "Social Campaign",
                            description: "Mô tả", owner: user,
                            config: {
                              "milestones" => [
                                { "title" => "Brief & Strategy", "offset_days" => 5 },
                                { "title" => "Launch", "offset_days" => 30 }
                              ],
                              "tasks" => [
                                { "title" => "Chốt brief", "milestone" => "Brief & Strategy", "priority" => "high", "offset_days" => 3 },
                                { "title" => "Không gắn milestone", "priority" => "low" }
                              ],
                              "brief_data" => { "business_goal" => "x" }
                            })
  end

  it "clone milestones + tasks vào campaign mới, KHÔNG mutate template" do
    start = Date.new(2026, 8, 1)
    campaign = described_class.call(org: org, user: user, template: template,
                                    client: client, name: "From template", start_date: start)
    expect(campaign.owner).to eq(user)
    expect(campaign.milestones.count).to eq(2)
    expect(campaign.milestones.find_by(title: "Brief & Strategy").due_at.to_date).to eq(start + 5.days)
    expect(campaign.tasks.count).to eq(2)
    expect(campaign.tasks.find_by(title: "Chốt brief").milestone.title).to eq("Brief & Strategy")
    expect(campaign.tasks.find_by(title: "Chốt brief").priority).to eq("high")
    expect(campaign.brief_data["business_goal"]).to eq("x")

    template.reload
    expect(template.config["milestones"].size).to eq(2) # nguyên vẹn
    expect(ProjectTemplate.count).to eq(1)
  end
end
