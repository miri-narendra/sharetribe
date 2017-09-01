class AddCustomerIdToStripeAccounts < ActiveRecord::Migration
  def change
    add_column :stripe_accounts, :stripe_customer_id, :string
  end
end
