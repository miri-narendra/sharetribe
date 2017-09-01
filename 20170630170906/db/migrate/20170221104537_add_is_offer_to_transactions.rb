class AddIsOfferToTransactions < ActiveRecord::Migration
  def change
    add_column :transactions, :is_offer, :boolean
  end
end
