require "rails_helper"

RSpec.describe Facebook::TokenCipher do
  it "mã hoá rồi giải mã lại đúng, ciphertext không chứa plaintext" do
    cipher = described_class.encrypt("EAAtokensecret123")
    expect(cipher).not_to include("EAAtokensecret")
    expect(described_class.decrypt(cipher)).to eq("EAAtokensecret123")
  end

  it "dùng khoá riêng khi FACEBOOK_TOKEN_ENCRYPTION_KEY được đặt — khoá khác thì không giải mã được" do
    cipher = with_env("FACEBOOK_TOKEN_ENCRYPTION_KEY" => "key-one") { described_class.encrypt("abc") }
    with_env("FACEBOOK_TOKEN_ENCRYPTION_KEY" => "key-one") { expect(described_class.decrypt(cipher)).to eq("abc") }
    with_env("FACEBOOK_TOKEN_ENCRYPTION_KEY" => "key-two") do
      expect { described_class.decrypt(cipher) }.to raise_error(Facebook::ConfigurationError)
    end
  end

  it "model không lộ token qua inspect/serializable_hash" do
    conn = build(:facebook_page_connection, access_token: "EAAsupersecret")
    expect(conn.inspect).not_to include("EAAsupersecret")
    expect(conn.inspect).to include("[FILTERED]")
    expect(conn.serializable_hash.keys).not_to include("access_token_ciphertext")
    expect(conn.to_json).not_to include("EAAsupersecret")
    expect(conn.access_token).to eq("EAAsupersecret")
  end
end
