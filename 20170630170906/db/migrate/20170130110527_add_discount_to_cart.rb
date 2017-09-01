class AddDiscountToCart < ActiveRecord::Migration
  def change
    add_column :carts, :discount_cents, :integer, default: 0
  end
end
