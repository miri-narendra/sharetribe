class CreateCarts < ActiveRecord::Migration
  def change
    create_table :carts do |t|
      t.references :community
      t.references :transaction
      t.string :pickup_location
      t.string :dropoff_location
      t.boolean :housekeeping_kit

      t.timestamps null: false
    end
  end
end
