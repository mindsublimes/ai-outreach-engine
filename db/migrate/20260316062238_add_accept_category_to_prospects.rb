class AddAcceptCategoryToProspects < ActiveRecord::Migration[8.0]
  def change
    add_column :prospects, :accept_category, :string
  end
end
