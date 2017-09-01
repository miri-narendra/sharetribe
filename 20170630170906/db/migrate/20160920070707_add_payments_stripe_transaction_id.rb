class AddPaymentsStripeTransactionId < ActiveRecord::Migration
  def up
    add_column :payments, :stripe_transaction_id, :string
  end

  def down
    remove_column :payments, :stripe_transaction_id
  end
end
