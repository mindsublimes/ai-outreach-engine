class AddPerksUrlToReferencePartners < ActiveRecord::Migration[8.0]
  def change
    add_column :reference_partners, :perks_url, :string
  end
end
