class CreateOtherFees < ActiveRecord::Migration
  def change
    create_table :other_fees do |t|
      t.references :cart
      t.string :name
      t.integer :amount_cents
      t.string :currency
      t.index :cart_id
    end
  end
end
