require "rails_helper"

RSpec.describe Facebook::Posts::Backoff do
  it "tăng theo luỹ thừa 2 từ 1 phút và chặn trần 30 phút" do
    expect(described_class.delay_seconds(1, jitter: false)).to eq(60)
    expect(described_class.delay_seconds(2, jitter: false)).to eq(120)
    expect(described_class.delay_seconds(3, jitter: false)).to eq(240)
    expect(described_class.delay_seconds(5, jitter: false)).to eq(960)
    expect(described_class.delay_seconds(10, jitter: false)).to eq(1800)
  end

  it "jitter không vượt 20%" do
    50.times { expect(described_class.delay_seconds(2)).to be_between(120, 144) }
  end
end
