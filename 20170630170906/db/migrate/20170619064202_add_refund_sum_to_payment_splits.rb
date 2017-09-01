class AddRefundSumToPaymentSplits < ActiveRecord::Migration
  def change
    add_column :payment_splits, :refund_cents, :integer
  end
end
