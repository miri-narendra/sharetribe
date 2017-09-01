class AddCommissionToPayments < ActiveRecord::Migration
  def change
    add_column :payments, :commission_cents, :integer
  end
end
