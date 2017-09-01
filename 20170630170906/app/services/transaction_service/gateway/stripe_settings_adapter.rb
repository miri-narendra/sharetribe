module TransactionService::Gateway
  class StripeSettingsAdapter < SettingsAdapter

    #PaymentSettingsStore = TransactionService::Store::PaymentSettings

    def configured?(community_id:, author_id:)
      #TODO review how this should be implemented, currently we cut it sort by 
      #using StripeSaleService directly in controller
      
      true
      #payment_settings = Maybe(PaymentSettingsStore.get_active(community_id: community_id))
      #                   .select {|set| paypal_settings_configured?(set)}

      #personal_account_verified = paypal_account_verified?(community_id: community_id, person_id: author_id, settings: payment_settings)
      #community_account_verified = paypal_account_verified?(community_id: community_id)
      #payment_settings_available = payment_settings.map {|_| true }.or_else(false)

      #[personal_account_verified, community_account_verified, payment_settings_available].all?
    end

    def tx_process_settings(opts_tx)
      #currency = opts_tx[:unit_price].currency
      #p_set = PaymentSettingsStore.get_active(community_id: opts_tx[:community_id])

      #{minimum_commission: Money.new(p_set[:minimum_transaction_fee_cents], currency),
      # commission_from_seller: p_set[:commission_from_seller],
      # automatic_confirmation_after_days: p_set[:confirmation_after_days]}

      {minimum_commission: Money.new(0, 'USD'),
       commission_from_seller: 0,
       automatic_confirmation_after_days: 14}
    end
  end
end
