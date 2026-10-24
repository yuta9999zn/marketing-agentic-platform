require "rails_helper"

RSpec.describe Ai::Gateway do
  let(:org) { create(:organization) }
  let(:user) { create(:user) }

  it "chạy offline với Fake adapter và ghi audit row chỉ chứa hash" do
    schema = { "type" => "object", "required" => ["a"], "properties" => { "a" => { "type" => "string" } } }
    fake = ->(_p) { { a: "hello" }.to_json }
    gw = described_class.new(org: org, user: user, fake_completion: fake)
    result = gw.generate_structured(prompt: "test", task: "unit.test", schema: schema)

    expect(result).to eq({ "a" => "hello" })
    expect(gw.provider_label).to eq("fake")

    call = AiCall.last
    expect(call.task).to eq("unit.test")
    expect(call.method).to eq("internal")
    expect(call.prompt_sha).to match(/\A[0-9a-f]{64}\z/)
    expect(call.output_sha).to match(/\A[0-9a-f]{64}\z/)
  end

  it "từ chối consent external khi master switch tắt" do
    schema = { "type" => "object", "properties" => {} }
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("AI_EXTERNAL_ENABLED").and_return("false")
    gw = described_class.new(org: org, user: user)
    expect {
      gw.generate_structured(prompt: "x", task: "t", schema: schema, consent_external: true)
    }.to raise_error(Ai::Gateway::ConsentRequiredError)
  end
end
