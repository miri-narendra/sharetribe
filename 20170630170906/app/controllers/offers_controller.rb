class OffersController < ApplicationController
  respond_to :html, :js

  include ListingActionFormData

  before_filter do |controller|
    controller.ensure_logged_in t("layouts.notifications.you_must_log_in_to_offer")
  end

  before_filter :fetch_context_transaction, only: [:new]
  before_filter :fetch_listing, only: [:create, :invoice]
  before_filter :fetch_payout_registration_guard

  before_filter :ensure_is_author
  before_filter :ensure_stripe_is_connected

  # Skip auth token check as current jQuery doesn't provide it automatically
  skip_before_filter :verify_authenticity_token

  #TODO we need a full transaction form here, not only a message
  BookingForm = FormUtils.define_form("BookingForm", :start_on, :end_on)
    .with_validations do
      validates :start_on, :end_on, presence: true
      validates_with DateValidator,
                     attribute: :end_on,
                     compare_to: :start_on,
                     restriction: :on_or_after
    end

  CartForm = FormUtils.define_form("CartForm",
     :pickup_location,
     :dropoff_location,
     :housekeeping_kit,
     :additional_miles,
     :additional_generator_hours,
     :total_miles,
     :total_generator_hours,
  )

  PostPayMessageForm = FormUtils.define_form("ListingConversation",
    :content,
    :sender_id,
    :contract_agreed,
    :delivery_method,
    :quantity,
    :listing_id
   ).with_validations {
    validates_presence_of :listing_id
    validates :delivery_method, inclusion: { in: %w(shipping pickup), message: "%{value} is not shipping or pickup." }, allow_nil: true
  }

  PostPayBookingForm = FormUtils.merge("ListingConversation", PostPayMessageForm, BookingForm, CartForm)

  MessageForm = Form::Message

  def new
    prepare_offer_form_from_context
    path_to_payment_settings = payment_settings_path(@current_community.payment_gateway.gateway_type, @current_user)

    #TODO we need a full transaction form here, not only a message

    delivery_opts = delivery_config(@listing.require_shipping_address, @listing.pickup_enabled, @listing.shipping_price, @listing.shipping_price_additional, @listing.currency)

    # locals for listing_actions_booking_form partial
    view_locals = {
      delivery_opts: delivery_opts,
      listing_unit_type: @listing.unit_type,
      is_author: (@current_user == @listing.author),
    }

    # locals for message form
    view_locals.merge!({
      message_form: MessageForm.new
    })

    # locals for change listing select and renter
    view_locals.merge!({
      open_listings: @current_user.listings.currently_open,
      selected_listing: @listing,
      renter: @renter
    })

    render(locals: view_locals)
  end

  def create
    payment_type = MarketplaceService::Community::Query.payment_type(@current_community.id)
    conversation_params = params[:listing_conversation]
    conversation_params.merge!(params[:cart])

    post_pay_form = PostPayBookingForm.new(conversation_params.merge({
      start_on: TransactionViewUtils.parse_booking_date(params[:start_on]),
      end_on: TransactionViewUtils.parse_booking_date(params[:end_on]),
      listing_id: @listing.id,
    }))

    delivery_method = delivery_config(@listing.require_shipping_address, @listing.pickup_enabled, @listing.shipping_price, @listing.shipping_price_additional, @listing.currency)

    unless post_pay_form.valid?
      return render_error_response(request.xhr?,
        post_pay_form.errors.full_messages.join(", "),
       { action: :book, start_on: TransactionViewUtils.stringify_booking_date(start_on), end_on: TransactionViewUtils.stringify_booking_date(end_on) })
    end

    renter_id = params[:renter_id]
    cart = TransactionService::Cart.get_or_create(listing: @listing)
    duration = DateUtils.duration_nights(post_pay_form.start_on, post_pay_form.end_on, cart.minimum_duration)

    process = TransactionService::API::Api.processes.get(community_id: @current_community.id, process_id: @listing.transaction_process_id).data
    gateway = MarketplaceService::Community::Query.payment_type(@current_community.id)

    additional_miles = TransactionService::Cart.calculate_additional_miles(post_pay_form.total_miles, cart, duration)
    additional_generator_hours = TransactionService::Cart.calculate_additional_generator_hours(post_pay_form.total_generator_hours, cart, duration)

    listing_conversation = TransactionService::Transaction.create( {
      transaction: {
        is_offer: true,
        payment_type: payment_type,
        community_id: @current_community.id,
        listing_id: @listing.id,
        listing_title: @listing.title,
        starter_id: renter_id,
        listing_author_id: @listing.author.id,
        listing_quantity: duration,
        unit_type: @listing.unit_type,
        unit_price: @listing.price,
        unit_tr_key: @listing.unit_tr_key,
        payment_gateway: process[:process] == :none ? :none : gateway, # TODO This is a bit awkward
        payment_process: process[:process],
        booking_fields: {
          start_on: post_pay_form.start_on,
          end_on: post_pay_form.end_on
        },
        cart_fields: {
          pickup_location:  post_pay_form.pickup_location,
          dropoff_location: post_pay_form.dropoff_location,
          housekeeping_kit: checkbox_to_boolean(post_pay_form.housekeeping_kit),
          additional_miles: additional_miles,
          additional_generator_hours:  additional_generator_hours,
        }
      }
    })
    @listing_conversation = Transaction.find_by(id: listing_conversation.data[:transaction][:id])

    other_fees_attributes = {}
    if params[:transaction][:cart_attributes][:other_fees_attributes].present?
      params[:transaction][:cart_attributes][:other_fees_attributes].each_pair do |key, other_fee|
        next if other_fee[:_destroy] == "1"
        other_fees_attributes[key] = {
          amount_cents: Monetize.parse(other_fee[:amount]).cents,
          name: other_fee[:name]
        }
      end
    end
    @listing_conversation.cart.update_attributes({
      security_deposit: Monetize.parse(params[:transaction][:cart_attributes][:security_deposit]),
      pickup_dropoff_fee: Monetize.parse(params[:transaction][:cart_attributes][:pickup_dropoff_fee]),
      discount: Monetize.parse(params[:transaction][:cart_attributes][:discount]),
      other_fees_attributes: other_fees_attributes
    }, without_protection: true)

    @payment = @current_community.payment_gateway.new_payment
    @payment.community = @current_community
    @payment.tx = @listing_conversation
    @payment.status = 'pending'
    @payment.payer_id = renter_id
    @payment.recipient_id = @current_user.id

    #TODO context conversation has to be replaced with the real data
    transaction_hash = TransactionService::Transaction.get(transaction_id: @listing_conversation.id, community_id: @current_community.id).data
    @payment.default_sum(transaction_hash, Maybe(@current_community).vat.or_else(0))
    @payment.save
    #TODO make sure the payment's adjusted_sum price is set

    message_params = params[:message]
    message_params[:content] = message_params[:content].present? ? message_params[:content] : "no notes added"

    message = MessageForm.new(message_params.merge({ conversation_id: @listing_conversation.id }))
    if(message.valid?)
      @listing_conversation.conversation.messages.create({content: message.content}.merge(sender_id: @current_user.id))
    end

    MarketplaceService::Transaction::Command.transition_to(@listing_conversation.id, :accepted, {action: :create_offer})
    MarketplaceService::Transaction::Command.mark_as_unseen_by_other(@listing_conversation.id, @current_user.id)
    Delayed::Job.enqueue(AutomaticOfferCancelingJob.new(@listing_conversation.id, @current_community.id), :priority => 9, :run_at => @listing_conversation.booking.start_on.at_end_of_day)

    if @listing_conversation.errors.empty?
      flash[:notice] = t("layouts.notifications.offer_created")
      redirect_to person_transaction_path(person_id: @current_user.id, id: @listing_conversation.id)
    else
      flash.now[:notice] = t("layouts.notifications.offer_create_error")
      render :new, locals: {
        delivery_opts: delivery_method,
        listing_unit_type: @listing.unit_type,
        is_author: (@current_user == @listing.author),
        open_listings: @current_user.listings.currently_open,
        selected_listing: @listing,
        renter: @listing_conversation.starter,
        message_form: MessageForm.new
      }
    end
  end

  def invoice
    prepare_offer_form_from_form_data
    render layout: nil
  end

  private

  def prepare_offer_form_from_context
    @listing_conversation = initialize_transaction_from_context(@context_transaction)
    @payment = @listing_conversation.payment
    @action = 'accept'
  end

  def prepare_offer_form_from_form_data
    @listing_conversation = initialize_transaction_from_form_data(params)
    @payment = @listing_conversation.payment
    @action = 'accept'
  end

  def ensure_is_author
    unless @listing.author == @current_user
      flash[:error] = "Only listing author can perform the requested action"
      redirect_to (session[:return_to_content] || root)
    end
  end

  def ensure_stripe_is_connected
    if @listing.author == @current_user && (@current_user.stripe_account.nil? || @current_user.stripe_account.stripe_publishable_key.nil?)
      flash[:error] = "Please connect your Stripe account before accepting or rejecting a request"
      redirect_to new_stripe_settings_payment_path
    end
  end

  def initialize_transaction_from_context(context_transaction)
    transaction = Transaction.new

    transaction.listing = context_transaction.listing
    transaction.starter = context_transaction.starter
    transaction.booking = context_transaction.booking #TODO don't reuse the booking, make a clone from this one
    transaction.cart = context_transaction.cart #TODO don't reuse the cart, make a clone from this one
    transaction.community = @current_community

    payment = initialize_payment(transaction)

    #TODO context conversation has to be replaced with the real data
    transaction_hash = TransactionService::Transaction.get(transaction_id: context_transaction.id, community_id: @current_community.id).data
    payment.default_sum(transaction_hash, Maybe(@current_community).vat.or_else(0))

    transaction.payment = payment
    transaction
  end

  # This function partially does all the steps that a TransactionService::Transaction.create does
  # we just initialize an object that has all the necessary data to display the offer form
  # and the invoice form
  def initialize_transaction_from_form_data(offer_params)
    transaction = Transaction.new

    transaction.community = @current_community

    starter = Person.find_by(id: offer_params[:renter_id])
    transaction.starter = starter

    listing = Listing.where(author: @current_user).currently_open.find_by(id: offer_params[:listing_id])
    transaction.listing = listing
    # from PostPayTransactionsController#create
    transaction.unit_price = listing.price

    # from TransactionService::Cart#initialize
    cart = initialize_cart_from_listing(listing, transaction)

    # from TransactionService::Store::Transaction#from_model
    # ordering is important - for booking we need minimum_duration from cart, that is extraced by cart service from listing
    #TODO to make life simpler, refactor cart.minimum_duration to be stored in booking.minimum_duration
    booking_hash = initialize_booking_hash(offer_params, @listing, cart.minimum_duration)
    transaction.booking = Booking.new( booking_hash[:booking].select{|key, value| key.to_s.match(/_on$/)} )
    #now we need to set transaction's listing_quantity

    #NOTE transaction.booking.duration returns day count, not night count
    transaction.listing_quantity = booking_hash[:booking][:duration]

    # from TransactionService::Store::Transaction#from_model -> add_opt_cart
    # most importantly assigns cart_hash[:cart][:total_sum] = cart.total_sum
    cart = update_cart_with_params(offer_params, cart, booking_hash[:booking][:duration])

    # from Cart (model)
    transaction.cart = cart

    transaction_hash = EntityUtils.model_to_hash(transaction)
                       .merge({unit_price: transaction.unit_price, minimum_commission: transaction.minimum_commission, shipping_price: transaction.shipping_price })
    transaction_hash.merge!(booking_hash)
    transaction_hash.merge!(cart_to_hash(cart))
    payment = initialize_payment(transaction)
    payment.default_sum(transaction_hash, Maybe(@current_community).vat.or_else(0))
    transaction.payment = payment

    transaction
  end

  def initialize_booking_hash(offer_params, listing, minimum_duration)
    hash = {}
    booking_data = EntityUtils.model_to_hash(::Booking.new)
    booking_data[:start_on] = TransactionViewUtils.parse_booking_date(offer_params[:start_on])
    booking_data[:end_on] = TransactionViewUtils.parse_booking_date(offer_params[:end_on])
    booking_data[:minimum_duration] = minimum_duration
    duration = TransactionService::Store::Transaction.booking_duration(booking_data)
    booking_data[:duration] = duration

    hash.merge!(booking: TransactionService::Store::Transaction::Booking.call(booking_data).merge({
      minimum_duration: minimum_duration,
      duration: duration
    }))
    hash
  end

  def initialize_cart_from_listing(listing, transaction)
    cart = TransactionService::Cart.initialize(listing: listing)
    cart.tx = transaction
    cart
  end

  def update_cart_with_params(offer_params, cart, duration)
    cart_params = offer_params[:cart].merge(offer_params[:transaction][:cart_attributes])


    #from CartsController#update
    #from CartsController#convert_nested_amount_to_cents
    other_fees_attributes = {}
    if cart_params[:other_fees_attributes].present?
      cart_params[:other_fees_attributes].each_pair do |key, other_fee|
        next if other_fee[:_destroy] == "1"
        other_fees_attributes[key] = {
          amount_cents: Monetize.parse(other_fee[:amount]).cents,
          name: other_fee[:name]
        }
      end
    end
    cart.assign_attributes({
      security_deposit: Monetize.parse(cart_params[:security_deposit]),
      pickup_dropoff_fee: Monetize.parse(cart_params[:pickup_dropoff_fee]),
      discount: Monetize.parse(cart_params[:discount]),
      other_fees_attributes: other_fees_attributes
    }, without_protection: true)

    #from PostPayTransactionController#book
    total_miles = cart_params.delete(:total_miles)
    total_generator_hours = cart_params.delete(:total_generator_hours)
    cart_params[:additional_miles] = TransactionService::Cart.calculate_additional_miles(total_miles, cart, duration)
    cart_params[:additional_generator_hours] = TransactionService::Cart.calculate_additional_generator_hours(total_generator_hours, cart, duration)

    cart_data = EntityUtils.model_to_hash(cart)
    cart_data.merge!({
      pickup_location:                 cart_params[:pickup_location],
      dropoff_location:                cart_params[:dropoff_location],
      housekeeping_kit:                checkbox_to_boolean(cart_params[:housekeeping_kit]),
      additional_miles:                cart_params[:additional_miles],
      additional_generator_hours:      cart_params[:additional_generator_hours],
    })

    cart_hash = TransactionService::Store::Transaction::Cart.call(cart_data)
    cart_hash.delete_if{|key, value| key == :other_fees}
    cart.assign_attributes(cart_hash)

    cart
  end

  def cart_to_hash(cart)
    cart_data = EntityUtils.model_to_hash(cart)

    {}.merge(cart: TransactionService::Store::Transaction::Cart.call(cart_data).merge({
      total_sum: cart.total_sum
    }))
  end

  def initialize_payment(transaction)
    #TODO extract concern with AcceptConversationsController#prepare_accept_or_reject_form
    payment = @current_community.payment_gateway.new_payment
    payment.community = @current_community
    payment.tx = transaction
    payment
  end

  def fetch_context_transaction
    @context_transaction = Transaction.where(community_id: @current_community, listing_author_id: @current_user)
                                      .find_by(id: params[:transaction_id])
    @listing = @context_transaction.listing
    @renter = @context_transaction.starter
  end

  def fetch_listing
    @listing = Listing.where(community_id: @current_community, author_id: @current_user)
                                  .currently_open
                                  .find_by(id: params[:listing_id])
  end

  def fetch_payout_registration_guard
    @payout_registration_missing = PaymentRegistrationGuard.new(@current_community, @current_user, @listing).requires_registration_before_accepting?
  end

  def checkbox_to_boolean(checkbox_value)
    ActiveRecord::ConnectionAdapters::Column::TRUE_VALUES.include?(checkbox_value)
  end
end
