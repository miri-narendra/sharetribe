#
# This class makes Stripe calls thread-safe even though we're using
# different configurations per Stripe call
#
class StripeApi
  class << self

    @@mutex = Mutex.new

    def payment_gateway_for(community)
      payment_gateway = StripePaymentGateway.where(community_id: community.id, stripe_livemode: APP_CONFIG.stripe_livemode).first
      payment_gateway
    end

    #=== Registering merchant via Stripe OAuth ===
    #
    # Stripe tokens do not expire unless the user deauthorizes the app
    # We can simulate token expiration in production by connecting a user and then
    # deauthorizing the apps access to the users stripe account from stripe dashboard
    #
    #TODO
    #1) make sure you are correctly handling deauthorized apps
    #2) Is there a way to check if we have received all deauthorisation webhooks
    #   or should we periodically refresh all tokens to see if we get errors?
    #

    def configure_oauth_for(payment_gateway)
      options = {
        site: 'https://connect.stripe.com',
        authorize_url: '/oauth/authorize',
        token_url: '/oauth/token'
      }
      client_id = payment_gateway.stripe_client_id
      api_key = payment_gateway.stripe_api_key
      client = OAuth2::Client.new(client_id, api_key, options)
      return client
    end

    def with_stripe_oauth_config(community, &block)
      payment_gateway = payment_gateway_for(community)
      oauth_client = configure_oauth_for(payment_gateway)
      return_value = block.call(oauth_client)
    end

    #GET https://connect.stripe.com/oauth/authorize
    #this function just generates an url, that the user must follow to connect
    #stripe via oauth (i.e. tell stripe that this app is allowed to handle the
    #users account)
    #
    #for this to work:
    #1) make sure in https://dashboard.stripe.com/account/applications/settings
    #   the redirect URIs are set to the same that you are passing as parameters
    #   for the authorize/connect_url other wise you will get
    #   error=invalid_redirect_uri
    #   you can use ngrok to allow redirect to locall project
    #2) in development mode if you open the authorize/connect_url it will automatically
    #   redirect you to the redirect_url with error=access_denied
    #3) to get a successfull connection, go to https://dashboard.stripe.com/account/applications/settings
    #   and click the "Test the OAuth flow" link, that will open a form. While
    #   the Stripe account is in test mode at the top of the page will be a
    #   notification with a link "Skip this account form". It will throw you to
    #   the redirect url adding the code=parameter, that gives you access to
    #   the user's account

    def create_merchant_account_url(redirect_uri, community)
      with_stripe_oauth_config(community) do | oauth_client |
        #this corresponds to
        #https://stripe.com/docs/connect/standalone-accounts
        #configuring oauth + creating the url - client.auth_code.authorize_url(params)
        params = {
          scope: 'read_write',
          redirect_uri: redirect_uri
        }
        oauth_client.auth_code.authorize_url(params)
      end
    end

    # POST https://connect.stripe.com/oauth/token
    # This endpoint is used both for turning an authorization_code into an
    # access_token, and for getting a new access token using a refresh_token.
    def create_merchant_account_callback(auth_code, community)
      with_stripe_oauth_config(community) do | oauth_client |
        oauth_client.auth_code.get_token(auth_code, :params => {:scope => 'read_write'})
      end
    end

    #=== Selling ===

    def configure_payment_for(payment_gateway)
      #client_id = community.payment_gateway.stripe_client_id
      Stripe.api_key = payment_gateway.stripe_api_key
    end

    def reset_configurations
      Stripe.api_key = ""
    end

    # This method should be used for all actions that require setting correct
    # Merchant details for the Stripe gem
    def with_stripe_payment_config(community, &block)
      @@mutex.synchronize {
        payment_gateway = payment_gateway_for(community)
        configure_payment_for(payment_gateway)

        return_value = block.call(payment_gateway)

        reset_configurations()

        return return_value
      }
    end

    def register_customer(community, email, card_token)
      with_stripe_payment_config(community) do | payment_gateway |
        Stripe::Customer.create(
          email: email,
          card: card_token
        )
      end
    end

    # used for stripe button in app/views/stripe_payments/edit.haml
    def merchant_publishable_key(community)
      with_stripe_payment_config(community) do | payment_gateway |
        payment_gateway.stripe_publishable_key
      end
    end


    def charge(community, charge_params, charge_options={})
      with_stripe_payment_config(community) do | payment_gateway |
        result = Stripe::Charge.create(charge_params, charge_options)
        PAYMENT_EVENT_LOG.info("Stripe::Charge.create result: #{result}")
        result
      end
    end

    def update_customer(community, customer_id, token)
      with_stripe_payment_config(community) do | payment_gateway |
        customer = Stripe::Customer.retrieve(customer_id)
        customer.source = token
        customer.save
        customer
      end
    end

    def create_token(community, customer_id, account_id)
      with_stripe_payment_config(community) do | payment_gateway |
        Stripe::Token.create({customer: customer_id}, {stripe_account: account_id})
      end
    end

    def refund(community, charge_id, amount, account_id)
      with_stripe_payment_config(community) do | payment_gateway |
        Stripe::Refund.create({:charge => charge_id, :amount => amount}, {stripe_account: account_id})
      end
    end

  end
end
