class AddPaymentSplits < ActiveRecord::Migration
  def change
    create_table :payment_splits do |t|
      t.references :payment, index: true, foreign_key: true
      t.string     :status
      t.integer    :sum_cents
      t.integer    :commission_cents
      t.string     :currency
      t.string     :braintree_transaction_id
      t.timestamps
    end
  end
end
