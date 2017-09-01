class AddFieldsToCart < ActiveRecord::Migration
  def change
    add_column :carts, :currency, :string
    add_column :carts, :additional_miles_price_per_mile_cents, :integer
    add_column :carts, :generator_hours_price_per_hour_cents, :integer
    add_column :carts, :cleaning_fee_cents, :integer
    add_column :carts, :housekeeping_kit_price_cents, :integer
    add_column :carts, :dump_water_fee_cents, :integer
    add_column :carts, :security_deposit_cents, :integer
    add_column :carts, :delivery_fee_per_mile, :string
    add_column :carts, :cancellation_policy, :string
  end
end
