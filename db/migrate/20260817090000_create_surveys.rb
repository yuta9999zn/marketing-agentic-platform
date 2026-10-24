class CreateSurveys < ActiveRecord::Migration[8.0]
  def change
    # Khảo sát gắn với campaign: thu thập phản hồi thật để AI phân tích thành
    # insight đưa vào brief — thay vì để AI đoán chân dung khách hàng.
    create_table :surveys do |t|
      t.references :campaign, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.string :status, null: false, default: "draft" # draft | open | closed
      t.json :questions, default: []                   # [{key, label, kind}]
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    create_table :survey_responses do |t|
      t.references :survey, null: false, foreign_key: true
      t.json :answers, default: {}
      t.string :respondent_label # tên/nhãn tự khai, không bắt buộc có tài khoản
      t.timestamps
    end
    add_index :survey_responses, %i[survey_id created_at]
  end
end
