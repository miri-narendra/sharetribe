class AddStripeTransactionIdToPaymentSplits < ActiveRecord::Migration
  def change
    add_column :payment_splits, :stripe_transaction_id, :string
  end
end
