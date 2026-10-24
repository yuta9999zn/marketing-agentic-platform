class CreateCoreSchema < ActiveRecord::Migration[8.0]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.string :slug, null: false, index: { unique: true }
      t.timestamps
    end

    create_table :users do |t|
      t.string :email, null: false, index: { unique: true }
      t.string :name, null: false
      t.string :password_digest, null: false
      t.timestamps
    end

    create_table :memberships do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "member"
      t.timestamps
      t.index %i[organization_id user_id], unique: true
    end

    create_table :invitations do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :email, null: false
      t.string :role, null: false
      t.string :token, null: false, index: { unique: true }
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.datetime :accepted_at
      t.references :invited_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    create_table :clients do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :industry
      t.text :notes
      t.timestamps
    end

    create_table :campaigns do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.text :objective
      t.date :start_date
      t.date :end_date
      t.timestamps
    end

    create_table :campaign_collaborators do |t|
      t.references :campaign, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :access, null: false, default: "view" # view | comment
      t.timestamps
      t.index %i[campaign_id user_id], unique: true
    end

    create_table :artifacts do |t|
      t.references :campaign, null: false, foreign_key: true
      t.string :kind, null: false # brief | persona | content_plan | deliverable | image_prompt
      t.string :title, null: false
      t.text :body
      t.boolean :ai_generated, null: false, default: false
      t.json :ai_metadata, default: {}
      t.string :approval_status, null: false, default: "draft" # draft | pending | approved | changes_requested
      t.integer :version, null: false, default: 1
      t.boolean :template, null: false, default: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    create_table :artifact_versions do |t|
      t.references :artifact, null: false, foreign_key: true
      t.text :body
      t.integer :version, null: false
      t.boolean :ai_generated, null: false, default: false
      t.json :ai_metadata, default: {}
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    create_table :approvals do |t|
      t.references :artifact, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :decision, null: false # approved | rejected | changes_requested
      t.text :note
      t.timestamps
    end

    create_table :tasks do |t|
      t.references :campaign, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.references :assignee, foreign_key: { to_table: :users }
      t.date :due_date
      t.string :status, null: false, default: "open" # open | in_progress | done
      t.timestamps
    end

    create_table :comments do |t|
      t.references :campaign, null: false, foreign_key: true
      t.references :artifact
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end

    create_table :events do |t|
      t.references :campaign, null: false, foreign_key: true
      t.string :title, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :location
      t.text :agenda
      t.timestamps
    end

    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :kind, null: false
      t.json :payload, default: {}
      t.datetime :read_at
      t.timestamps
    end

    create_table :audit_logs do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :subject_type
      t.bigint :subject_id
      t.json :details, default: {}
      t.timestamps
    end

    # Mirror of the harness Audit middleware sink — hashes only, never raw text.
    create_table :ai_calls do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, foreign_key: { to_table: :users }
      t.string :task, null: false
      t.string :model, null: false
      t.string :method, null: false # internal | external
      t.string :prompt_sha, null: false
      t.string :output_sha
      t.boolean :repaired, null: false, default: false
      t.integer :latency_ms
      t.string :status, null: false, default: "ok"
      t.timestamps
    end
  end
end
