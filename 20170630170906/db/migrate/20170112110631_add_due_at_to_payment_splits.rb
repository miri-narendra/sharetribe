class AddDueAtToPaymentSplits < ActiveRecord::Migration
  def up
    ActiveRecord::Base.transaction do
      add_column :payment_splits, :due_on, :date
      add_column :payment_splits, :paid_on, :date
      add_index :payment_splits, :due_on
      add_index :payment_splits, :paid_on
      ActiveRecord::Base.connection.execute("UPDATE payment_splits SET paid_on = DATE(updated_at), due_on = DATE(updated_at) WHERE status = 'paid'")
      Transaction.find_each do |transaction|
        if transaction.payment.present?
          schedule = TransactionService::PaymentSchedule.get(community_id: transaction.community_id, transaction_id: transaction.id)
          schedule.update_pending_payment_splits
        end
      end
    end
  end

  def down
    remove_index :payment_splits, :due_on
    remove_index :payment_splits, :paid_on
    remove_column :payment_splits, :due_on
    remove_column :payment_splits, :paid_on
  end
end
