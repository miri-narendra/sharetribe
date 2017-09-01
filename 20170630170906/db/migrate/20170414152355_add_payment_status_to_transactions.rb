class AddPaymentStatusToTransactions < ActiveRecord::Migration
  def change
    add_column :transactions, :payment_status, :string, limit: 255, after: :current_state, null: true, default: Transaction::NOT_PAID
  end
end
