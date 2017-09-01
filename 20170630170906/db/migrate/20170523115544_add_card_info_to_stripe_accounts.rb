class AddCardInfoToStripeAccounts < ActiveRecord::Migration
  def change
    add_column :stripe_accounts, :stripe_source_info, :string
  end
end
