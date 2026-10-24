class AddUserPrefsAndClientContacts < ActiveRecord::Migration[8.0]
  def change
    # Tùy chọn cá nhân: ngôn ngữ UI + cấu hình nhắc nhở (nhắc trước bao lâu, kênh nào).
    add_column :users, :locale, :string
    add_column :users, :reminder_lead_minutes, :integer, default: 1440, null: false
    add_column :users, :reminder_channel, :string, default: "in_app", null: false

    # CRM: đầu mối liên hệ của client/brand.
    add_column :clients, :contact_name, :string
    add_column :clients, :contact_email, :string
    add_column :clients, :contact_phone, :string
  end
end
