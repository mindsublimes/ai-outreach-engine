# frozen_string_literal: true

class CreateProspects < ActiveRecord::Migration[8.0]
  def change
    create_table :prospects do |t|
      t.string :url, null: false
      t.string :b2b_b2c_status, default: 'unknown', null: false
      t.text :research_summary
      t.string :company_name
      t.string :track, default: 'partner'
      t.string :category
      t.string :email
      t.string :status, default: 'pending', null: false
      t.boolean :is_b2b
      t.text :observation
      t.string :target_persona
      t.boolean :research_failed, default: false, null: false
      t.text :failure_reason
      t.text :generated_email_body
      t.string :first_name
      t.string :last_name
      t.string :job_title
      t.string :generated_email_subject
      t.string :business_type
      t.decimal :look_alike_score, precision: 3, scale: 2
      t.boolean :owner_operator_match
      t.string :priority
      t.boolean :is_scalable, default: false
      t.text :signals_detected

      t.timestamps
    end

    add_index :prospects, :url, unique: true
    add_index :prospects, :b2b_b2c_status
    add_index :prospects, :track
    add_index :prospects, :is_scalable
  end
end
