class StripeAccountsController < ApplicationController

  before_filter do |controller|
    controller.ensure_logged_in t("layouts.notifications.you_must_log_in_to_change_payment_settings")
  end

  # Commonly used paths
  before_filter do |controller|
    @create_url = create_stripe_settings_payment_url(locale: :en)
    @show_path = show_stripe_settings_payment_path(@current_user)
    @new_path = new_stripe_settings_payment_path(@current_user)
    @destroy_path = destroy_stripe_settings_payment_path(@current_user)

    @stripe_connect_uri = StripeOauthService.connect_merchant_request_url(@create_url, @current_community)
  end

  # New/create
  before_filter :ensure_user_does_not_have_connected_account, :only => [:new, :create]

  before_filter :ensure_user_does_not_have_account_for_another_community

  def new
    #TODO rewrite this comment!!!
    #
    #in the new form, the user will click a button that sends an OAuth request
    #to stipe and pass a client_id and callback_url
    #
    # client_id: we generate a unique tokent to send to stripe, so that we hide the customers
    #id on the platform
    # callback_url: should link to stripe_settings#create, that will be receive
    # a get request from stripe connect with success or error parameters
    # https://connect.stripe.com/oauth/authorize?response_type=code&client_id=ca_32D88BD1qLklliziD7gYQvctJIhWBSQ7&scope=read_write

    #INFO before filter sets @stripe_account


    render locals: { stripe_connect_url: @stripe_connect_uri }
  end

  def show
    #TODO here we should also call stripe and check if the account is still valid and the oauth token actually works
    redirect_to action: :new and return unless @current_user.stripe_account.present? && @current_user.stripe_account.access_token.present?

    @stripe_account = StripeAccount.find_by_person_id(@current_user.id)

    render locals: { form_action: @destroy_path, form_method: :get}
  end

  def create
    # stripe callback after user has registered or authenticated on stripe
    #
    # When the user arrives at Stripe, they’ll be prompted to allow or deny the
    # connection to your platform, and will then be sent to your redirect_uri page.
    # In the URL, we’ll pass along an authorization code:
    # https://stripe.com/connect/default/oauth/test?scope=read_write&code=AUTHORIZATION_CODE
    #
    # If the authorization was denied by the user, we’ll include an error instead:
    # https://stripe.com/connect/default/oauth/test?error=access_denied&error_description=The%20user%20denied%20your%20request

    if params[:error]
      StripeLog.error "received error from stripe: #{params[:error_description]} (#{params[:error]})"
      flash[:error] ||= t("layouts.notifications.cannot_connect_stripe_account.received_error", error_message: "#{params[:error_description]} (#{params[:error]})" )
      render :new, locals: { stripe_connect_url: @stripe_connect_uri } and return
    end

    if params[:code].blank?
      StripeLog.error "Did not receive authorization code from stripe"
      flash[:error] ||= t("layouts.notifications.cannot_connect_stripe_account.missing_authorization_code")
      render :new, locals: { stripe_connect_url: @stripe_connect_uri } and return
    end

    StripeLog.info "authorization code: #{params[:code]}"
    @stripe_account = StripeOauthService.save_account_after_connect_merchant_callback(params[:code], @current_user, @current_community)

    if @stripe_account.errors.empty?
      flash[:notice] = t("layouts.notifications.payment_details_add_successful")
      redirect_to @show_path
    else
      flash[:error] = @stripe_account.errors.full_messages
      render :new, locals: { stripe_connect_url: @stripe_connect_uri }
    end
  end

  def destroy
    @stripe_account = StripeAccount.find_by_person_id(@current_user.id)
    @stripe_account.destroy unless @stripe_account.nil?

    redirect_to action: :new
  end

  private

  # Before filter
  def ensure_user_does_not_have_connected_account
    @stripe_account = ensure_account_entry(@current_user, @current_community)

    unless @stripe_account.blank? || @stripe_account.access_token.blank?
      flash[:error] = t("layouts.notifications.cannot_connect_stripe_account.allready_connected")
      redirect_to @show_path
    end
  end

  # Before filter
  # Support for multiple Stripe account in multipe communities
  # is not implemented. Show error.
  def ensure_user_does_not_have_account_for_another_community
    @stripe_account = StripeAccount.find_by_person_id(@current_user.id)

    if @stripe_account
      # Stripe account exists
      if @stripe_account.community_id.present? && @stripe_account.community_id != @current_community.id
        # ...but is associated to different community
        account_community = Community.find(@stripe_account.community_id)
        flash[:error] = t("layouts.notifications.cannot_connect_stripe_account.account_allready_to_other_community", community_name: account_community.name(I18n.locale))

        error_msg = "User #{@current_user.id} tried to create a Stripe payment account for community #{@current_community.name(I18n.locale)} even though she has existing account for #{account_community.name(I18n.locale)}"
        StripeLog.error(error_msg)
        ApplicationHelper.send_error_notification(error_msg, "StripePaymentAccountError")
        redirect_to person_settings_path(@current_user)
      end
    end
  end

  # Give `stripe_account` and `new_status` candidate. Update the status, unless the status is already
  # active
  #
  # Background: If the webhook has already update the status to "active", we don't want to change it back
  # to pending. This may happen in sandbox environment, where the webhook is triggered very fast
  def update_status!(stripe_account, new_status)
    stripe_account.reload
    stripe_account.status = new_status if stripe_account.status != "active"
    stripe_account.save!
  end

  def ensure_account_entry(user, community)
    person_details = {
      person_id: user.id,
      community_id: community.id
    }

    StripeAccount.create(person_details) if StripeAccount.where(person_details).empty?
    StripeAccount.where(person_details).first
  end
end
