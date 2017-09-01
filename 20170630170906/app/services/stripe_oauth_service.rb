class StripeOauthService
  class << self

    def connect_merchant_request_url(redirect_uri, community)
      StripeApi.create_merchant_account_url(redirect_uri, community) 
    end

    def save_account_after_connect_merchant_callback(auth_code, user, community)

      token = StripeApi.create_merchant_account_callback(auth_code, community)

      stripe_account = StripeAccount.where(person_id: user.id)
        .where(community_id: community.id).first_or_create

      if token && token.token.present? 
        stripe_account.update_attributes({
          access_token: token.token,
          refresh_token: token.refresh_token,
          scope: token.params['scope'],
          livemode: token.params['livemode'],
          token_type: token.params['token_type'],
          stripe_user_id: token.params['stripe_user_id'],
          stripe_publishable_key: token.params['stripe_publishable_key']
        })
      else
        StripeLog.info "could not retrieve token"
        #TODO the error message should say thet the token could not be retrieved, try again later
        stripe_account.errors[:base] << t("layouts.notifications.payment_details_add_error")
      end

      return stripe_account
    end

  end
end

