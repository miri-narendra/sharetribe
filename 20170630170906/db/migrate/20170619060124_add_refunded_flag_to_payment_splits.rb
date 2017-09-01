class AddRefundedFlagToPaymentSplits < ActiveRecord::Migration
  def change
    add_column :payment_splits, :stripe_refund_id, :string
    add_column :payment_splits, :is_refunded, :boolean, default: false
  end
end
