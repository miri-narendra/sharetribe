class AddPickupDropoffFeeToCarts < ActiveRecord::Migration
  def change
    add_column :carts, :pickup_dropoff_fee_cents, :integer
  end
end
