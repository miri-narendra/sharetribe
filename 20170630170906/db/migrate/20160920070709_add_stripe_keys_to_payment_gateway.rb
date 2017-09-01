class AddStripeKeysToPaymentGateway < ActiveRecord::Migration
  def change
    add_column :payment_gateways, :stripe_api_key, :string
    add_column :payment_gateways, :stripe_client_id, :string
    add_column :payment_gateways, :stripe_publishable_key, :string
    add_column :payment_gateways, :stripe_livemode, :boolean
  end
end
