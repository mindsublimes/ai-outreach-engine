# frozen_string_literal: true

class CreateReferencePartners < ActiveRecord::Migration[8.0]
  def change
    create_table :reference_partners do |t|
      t.string :url, null: false
      t.string :name
      t.text :about_summary
      t.text :products_summary
      t.text :owner_operator_indicators
      t.integer :display_order, default: 0, null: false
      t.datetime :last_scraped_at
      t.string :domain
      t.string :category
      t.text :dna_signals  # JSON stored as text for SQLite compatibility

      t.timestamps
    end

    add_index :reference_partners, :url, unique: true
    add_index :reference_partners, :display_order
    add_index :reference_partners, :domain
    add_index :reference_partners, :category
  end
end
