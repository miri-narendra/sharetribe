class AddAdjustedSumToPayments < ActiveRecord::Migration
  def change
    add_column :payments, :adjusted_sum_cents, :integer
  end
end
