class AddMinimumDurationToCart < ActiveRecord::Migration
  def change
    add_column :carts, :minimum_duration, :integer
  end
end
