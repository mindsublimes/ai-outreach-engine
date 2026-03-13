# frozen_string_literal: true

class CreateOutreachDrafts < ActiveRecord::Migration[8.0]
  def change
    create_table :outreach_drafts do |t|
      t.references :prospect, null: false, foreign_key: true
      t.string :subject, null: false
      t.text :body, null: false
      t.string :status, default: 'draft', null: false
      t.string :gmail_thread_id

      t.timestamps
    end

    add_index :outreach_drafts, :status
    add_index :outreach_drafts, :gmail_thread_id
  end
end
