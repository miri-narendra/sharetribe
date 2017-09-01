class PostPayTransactionsController < ApplicationController

  before_filter do |controller|
   controller.ensure_logged_in t("layouts.notifications.you_must_log_in_to_do_a_transaction")
  end

  before_filter :fetch_listing_from_params
  before_filter :ensure_listing_is_open
  before_filter :ensure_listing_author_is_not_current_user
  before_filter :ensure_authorized_to_reply
  before_filter :ensure_can_receive_payment, only: [:preauthorize, :preauthorized]

  SUBMIT_TYPES = [
    BOOKING = "booking",
    INQUIRY = "inquiry"
  ]

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
     :total_generator_hours
  )

  ContactForm = FormUtils.define_form("ListingConversation", :content, :sender_id, :listing_id, :community_id)
    .with_validations { validates_presence_of :content, :listing_id }

  BraintreeForm = Form::Braintree

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

  ListingQuery = MarketplaceService::Listing::Query
  BraintreePaymentQuery = BraintreeService::Payments::Query

  def new
    @listing_conversation = new_contact_form

    render "listing_conversations/new_with_payment", locals: {
      contact_form: @listing_conversation,
      contact_to_listing: create_transaction_path(:person_id => @current_user.id, :listing_id => @listing.id),
      listing: @listing
    }
  end

  def create
    contact_form = new_contact_form(params[:listing_conversation])

    if contact_form.valid?
      transaction_response = TransactionService::Transaction.create({
          transaction: {
            community_id: @current_community.id,
            listing_id: @listing.id,
            listing_title: @listing.title,
            starter_id: @current_user.id,
            listing_author_id: @listing.author.id,
            unit_type: @listing.unit_type,
            unit_price: @listing.price,
            unit_tr_key: @listing.unit_tr_key,
            listing_quantity: 1,
            content: contact_form.content,
            payment_gateway: @current_community.payment_gateway.gateway_type,
            payment_process: :postpay,
          }
        })

      unless transaction_response[:success]
        flash[:error] = "Sending the message failed. Please try again."
        return redirect_to search_path
      end

      transaction_id = transaction_response[:data][:transaction][:id]

      flash[:notice] = t("layouts.notifications.message_sent")
      Delayed::Job.enqueue(TransactionCreatedJob.new(transaction_id, @current_community.id))

      [3, 10].each do |send_interval|
        Delayed::Job.enqueue(
          AcceptReminderJob.new(
            transaction_id,
            @listing.author.id, @current_community.id),
          :priority => 9, :run_at => send_interval.days.from_now)
      end

      redirect_to session[:return_to_content] || search_path
    else
      flash[:error] = "Sending the message failed. Please try again."
      redirect_to search_path
    end
  end

  def book
    delivery_method = valid_delivery_method(delivery_method_str: params[:delivery],
                                            shipping: @listing.require_shipping_address,
                                            pickup: @listing.pickup_enabled)
    if(delivery_method == :errored)
      return redirect_to error_not_found_path
    end

    listing = ListingQuery.listing(params[:listing_id])

    cart_data = verified_cart_data(cart: params[:cart])
    total_miles = cart_data.delete(:total_miles)
    total_generator_hours = cart_data.delete(:total_generator_hours)

    cart = TransactionService::Cart.get_or_create(listing: listing)

    booking_data = verified_booking_data(params[:start_on], params[:end_on], cart)
    duration = booking_data[:duration]

    cart_data[:additional_miles] = TransactionService::Cart.calculate_additional_miles(total_miles, cart, duration)
    cart_data[:additional_generator_hours] = TransactionService::Cart.calculate_additional_generator_hours(total_generator_hours, cart, duration)
    cart.update_attributes(cart_data)

    vprms = view_params(listing: listing,
                        quantity: booking_data[:duration],
                        shipping_enabled: delivery_method == :shipping)

    if booking_data[:error].present?
      flash[:error] = booking_data[:error]
      return redirect_to listing_path(vprms[:listing][:id])
    end

    gateway_locals =
      if (vprms[:payment_type] == :braintree)
        braintree_gateway_locals(@current_community.id)
      else
        {}
      end

    form_action = nil
    view = nil
    if (params[:submit_type] && params[:submit_type] == PostPayTransactionsController::INQUIRY)
      form_action = post_pay_inquired_path(person_id: @current_user.id, listing_id: vprms[:listing][:id])
      view = "listing_conversations/post_pay_inquire"
    else
      form_action = post_pay_booked_path(person_id: @current_user.id, listing_id: vprms[:listing][:id])
      view = "listing_conversations/post_pay_book"
    end
      #case vprms[:payment_type]
      #when :braintree
      #  "listing_conversations/preauthorize"
      #when :paypal
      #  "listing_conversations/initiate"
      #else
      #  raise ArgumentError.new("Unknown payment type #{vprms[:payment_type]} for booking")
      #end

    community_country_code = LocalizationUtils.valid_country_code(@current_community.country)

    schedule = TransactionService::PaymentSchedule.new(
      community_id: @current_community.id,
      listing_price: vprms[:listing][:price],
      booking_start_on: booking_data[:start_on],
      booking_end_on:   booking_data[:end_on],
      duration: booking_data[:duration],
      cart: cart
    )

    due_now_sum = if (params[:submit_type] && params[:submit_type] == PostPayTransactionsController::INQUIRY)
                    nil
                  else
                    schedule.due_now_sum
                  end

    price_break_down_locals = TransactionViewUtils.price_break_down_locals({
      transaction_status: "pending",
      booking:  true,
      start_on: booking_data[:start_on],
      end_on:   booking_data[:end_on],
      duration: booking_data[:duration],
      cart: cart.to_hash,
      listing_price: vprms[:listing][:price],
      localized_unit_type: translate_unit_from_listing(vprms[:listing]),
      localized_selector_label: translate_selector_label_from_listing(vprms[:listing]),
      #subtotal: vprms[:subtotal],
      shipping_price: delivery_method == :shipping ? vprms[:shipping_price] : nil,
      paid_sum: schedule.paid_sum,
      due_now_sum: due_now_sum,
      second_payment_is_due_on: schedule.second_payment_is_due_on,
      second_payment_sum: schedule.second_payment_sum,
      security_deposit_is_due_on: schedule.security_deposit_is_due_on,
      security_deposit_sum: schedule.security_deposit_sum,
      subtotal: vprms[:subtotal],
      total: vprms[:total_price] + cart.cart_sum
    })

    render view, locals: {
      post_pay_form: PostPayBookingForm.new({
        start_on: booking_data[:start_on],
        end_on: booking_data[:end_on],
        pickup_location: cart_data[:pickup_location],
        dropoff_location: cart_data[:dropoff_location],
        housekeeping_kit: cart_data[:housekeeping_kit],
        additional_miles: cart_data[:additional_miles],
        additional_generator_hours: cart_data[:additional_generator_hours]
      }),
      country_code: community_country_code,
      listing: vprms[:listing],
      delivery_method: delivery_method,
      subtotal: vprms[:subtotal],
      author: query_person_entity(vprms[:listing][:author_id]),
      action_button_label: vprms[:action_button_label],
      expiration_period: MarketplaceService::Transaction::Entity.authorization_expiration_period(vprms[:payment_type]),
      form_action: form_action,
      price_break_down_locals: price_break_down_locals
    }.merge(gateway_locals)
  end

  def booked
    payment_type = MarketplaceService::Community::Query.payment_type(@current_community.id)
    conversation_params = params[:listing_conversation]

    start_on = DateUtils.from_date_select(conversation_params, :start_on)
    end_on = DateUtils.from_date_select(conversation_params, :end_on)
    post_pay_form = PostPayBookingForm.new(conversation_params.merge({
      start_on: start_on,
      end_on: end_on,
      listing_id: @listing.id,
    }))

    if @current_community.transaction_agreement_in_use? && conversation_params[:contract_agreed] != "1"
      #TODO VP fix error rendering
      return render_error_response(request.xhr?,
        t("error_messages.transaction_agreement.required_error"),
        { action: :book,
          start_on: TransactionViewUtils.stringify_booking_date(start_on),
          end_on: TransactionViewUtils.stringify_booking_date(end_on),
          cart: {
            pickup_location: conversation_params[:pickup_location],
            dropoff_location: conversation_params[:dropoff_location],
            housekeeping_kit: conversation_params[:housekeeping_kit],
            additional_miles: conversation_params[:additional_miles],
            additional_generator_hours: conversation_params[:additional_generator_hours]
          }
        })
    end

    delivery_method = valid_delivery_method(delivery_method_str: post_pay_form.delivery_method,
                                            shipping: @listing.require_shipping_address,
                                            pickup: @listing.pickup_enabled)
    if(delivery_method == :errored)
      return render_error_response(request.xhr?, "Delivery method is invalid.", action: :booked)
    end

    unless post_pay_form.valid?
      return render_error_response(request.xhr?,
        post_pay_form.errors.full_messages.join(", "),
       { action: :book, start_on: TransactionViewUtils.stringify_booking_date(start_on), end_on: TransactionViewUtils.stringify_booking_date(end_on) })
    end

    minimum_duration = TransactionService::Cart.get_or_create(listing: @listing).minimum_duration
    transaction_response = create_post_pay_transaction(
      payment_type: payment_type,
      community: @current_community,
      listing: @listing,
      user: @current_user,
      listing_quantity: DateUtils.duration_nights(post_pay_form.start_on, post_pay_form.end_on, minimum_duration),
      content: post_pay_form.content.present? ? post_pay_form.content : "no notes added",
      use_async: request.xhr?,
      delivery_method: delivery_method,
      shipping_price: @listing.shipping_price,
      bt_payment_params: params[:braintree_payment],
      booking_fields: {
        start_on: post_pay_form.start_on,
        end_on: post_pay_form.end_on
      },
      cart_fields: {
        pickup_location:  post_pay_form.pickup_location,
        dropoff_location: post_pay_form.dropoff_location,
        housekeeping_kit: post_pay_form.housekeeping_kit,
        additional_miles: post_pay_form.additional_miles,
        additional_generator_hours:  post_pay_form.additional_generator_hours
      }
    )

    transaction_id = transaction_response[:data][:transaction][:id]

    if transaction_response[:success]
      Delayed::Job.enqueue(TransactionCreatedJob.new(transaction_id, @current_community.id))
      Delayed::Job.enqueue(CommunityTransactionCreatedJob.new(transaction_id, @current_community.id))

      [1, 3].each do |send_interval|
        Delayed::Job.enqueue(
          AcceptReminderJob.new(
            transaction_id,
            @listing.author.id, @current_community.id),
          :priority => 9, :run_at => send_interval.days.from_now)
      end
    else
      error =
        if (payment_type == :paypal)
          t("error_messages.paypal.generic_error")
        else
          "An error occured while trying to create a new transaction: #{transaction_response[:error_msg]}"
        end

      return render_error_response(request.xhr?, error, { action: :book, start_on: TransactionViewUtils.stringify_booking_date(start_on), end_on: TransactionViewUtils.stringify_booking_date(end_on) })
    end

    case payment_type
    when :paypal
      if (transaction_response[:data][:gateway_fields][:redirect_url])
        return redirect_to transaction_response[:data][:gateway_fields][:redirect_url]
      else
        return render json: {
          op_status_url: transaction_op_status_path(transaction_response[:data][:gateway_fields][:process_token]),
          op_error_msg: t("error_messages.paypal.generic_error")
        }
      end
    when :braintree
      return redirect_to person_transaction_path(:person_id => @current_user.id, :id => transaction_id)
    when :stripe
      return redirect_to person_transaction_path(:person_id => @current_user.id, :id => transaction_id)
    end

  end

  def inquired
    payment_type = :none #MarketplaceService::Community::Query.payment_type(@current_community.id)
    conversation_params = params[:listing_conversation]

    start_on = DateUtils.from_date_select(conversation_params, :start_on)
    end_on = DateUtils.from_date_select(conversation_params, :end_on)
    post_pay_form = PostPayBookingForm.new(conversation_params.merge({
      start_on: start_on,
      end_on: end_on,
      listing_id: @listing.id,
    }))

    if @current_community.transaction_agreement_in_use? && conversation_params[:contract_agreed] != "1"
      #TODO VP fix error rendering
      return render_error_response(request.xhr?,
        t("error_messages.transaction_agreement.required_error"),
        { action: :inquire,
          start_on: TransactionViewUtils.stringify_booking_date(start_on),
          end_on: TransactionViewUtils.stringify_booking_date(end_on),
          cart: {
            pickup_location: conversation_params[:pickup_location],
            dropoff_location: conversation_params[:dropoff_location],
            housekeeping_kit: conversation_params[:housekeeping_kit],
            additional_miles: conversation_params[:additional_miles],
            additional_generator_hours: conversation_params[:additional_generator_hours]
          }
        })
    end

    delivery_method = valid_delivery_method(delivery_method_str: post_pay_form.delivery_method,
                                            shipping: @listing.require_shipping_address,
                                            pickup: @listing.pickup_enabled)
    if(delivery_method == :errored)
      return render_error_response(request.xhr?, "Delivery method is invalid.", action: :booked)
    end

    unless post_pay_form.valid?
      return render_error_response(request.xhr?,
        post_pay_form.errors.full_messages.join(", "),
       { action: :inquire, start_on: TransactionViewUtils.stringify_booking_date(start_on), end_on: TransactionViewUtils.stringify_booking_date(end_on) })
    end

    minimum_duration = TransactionService::Cart.get_or_create(listing: @listing).minimum_duration
    transaction_response = create_post_pay_transaction(
      payment_type: payment_type,
      community: @current_community,
      listing: @listing,
      user: @current_user,
      listing_quantity: DateUtils.duration_nights(post_pay_form.start_on, post_pay_form.end_on, minimum_duration),
      content: post_pay_form.content.present? ? post_pay_form.content : "no notes added",
      use_async: request.xhr?,
      delivery_method: delivery_method,
      shipping_price: @listing.shipping_price,
      bt_payment_params: params[:braintree_payment],
      booking_fields: {
        start_on: post_pay_form.start_on,
        end_on: post_pay_form.end_on
      },
      cart_fields: {
        pickup_location:  post_pay_form.pickup_location,
        dropoff_location: post_pay_form.dropoff_location,
        housekeeping_kit: post_pay_form.housekeeping_kit,
        additional_miles: post_pay_form.additional_miles,
        additional_generator_hours:  post_pay_form.additional_generator_hours
      }
    )

    transaction_id = transaction_response[:data][:transaction][:id]

    if transaction_response[:success]
      Delayed::Job.enqueue(InquiryTransactionCreatedJob.new(transaction_id, @current_community.id))
      Delayed::Job.enqueue(CommunityTransactionCreatedJob.new(transaction_id, @current_community.id))
    else
      error =
        if (payment_type == :paypal)
          t("error_messages.paypal.generic_error")
        else
          "An error occured while trying to create a new transaction: #{transaction_response[:error_msg]}"
        end

      return render_error_response(request.xhr?, error, { action: :book, start_on: TransactionViewUtils.stringify_booking_date(start_on), end_on: TransactionViewUtils.stringify_booking_date(end_on) })
    end

    if ["L6TFUXerfHJ_tvg6F6dTnA", "mgb54-MiUv3UFp_mYMvtOg", "qgfsOtdjMogaZJVedhRgbA"].include?(@listing.author_id)
      redirect_to about_gossrv_path
    else
      redirect_to person_transaction_path(:person_id => @current_user.id, :id => transaction_id), flash: {notice: "Request sent"}
    end
  end

  private

  def verified_booking_data(start_on, end_on, cart)
    booking_form = BookingForm.new({
      start_on: TransactionViewUtils.parse_booking_date(start_on),
      end_on: TransactionViewUtils.parse_booking_date(end_on)
    })

    if !booking_form.valid?
      { error: booking_form.errors.full_messages }
    else
      booking_form.to_hash.merge({
        duration: TransactionService::Cart.calculate_duration(booking_form.start_on, booking_form.end_on, cart)
      })
    end
  end

  def valid_delivery_method(delivery_method_str:, shipping:, pickup:)
    case [delivery_method_str, shipping, pickup]
    when matches([nil, true, false]), matches(["shipping", true, __])
      :shipping
    when matches([nil, false, true]), matches(["pickup", __, true])
      :pickup
    when matches([nil, false, false])
      nil
    else
      :errored
    end
  end

  def view_params(listing:, quantity: 1, shipping_enabled: false)
    payment_type = MarketplaceService::Community::Query.payment_type(@current_community.id)

    action_button_label = translate(listing[:action_button_tr_key])

    subtotal = listing[:price] * quantity
    shipping_price = shipping_price_total(listing[:shipping_price], listing[:shipping_price_additional], quantity)
    total_price = shipping_enabled ? subtotal + shipping_price : subtotal

    { listing: listing,
      payment_type: payment_type,
      action_button_label: action_button_label,
      subtotal: subtotal,
      shipping_price: shipping_price,
      total_price: total_price }
  end

  def verified_cart_data(cart:)
    cart_form = CartForm.new({
      pickup_location: cart['pickup_location'],
      dropoff_location: cart['dropoff_location'],
      housekeeping_kit: cart['housekeeping_kit'],
      total_miles: cart['total_miles'],
      total_generator_hours: cart['total_generator_hours']
    })
    if !cart_form.valid?
      { error: cart_form.errors.full_messages }
    else
      cart_form.to_hash
    end
  end

  def shipping_price_total(shipping_price, shipping_price_additional, quantity)
    Maybe(shipping_price)
      .map { |price|
        if shipping_price_additional.present? && quantity.present? && quantity > 1
          price + (shipping_price_additional * (quantity - 1))
        else
          price
        end
      }
      .or_else(nil)
  end

  def braintree_gateway_locals(community_id)
    braintree_settings = BraintreePaymentQuery.braintree_settings(community_id)

    {
      braintree_client_side_encryption_key: braintree_settings[:braintree_client_side_encryption_key],
      braintree_form: BraintreeForm.new
    }
  end

  def translate_unit_from_listing(listing)
    Maybe(listing).select { |l|
      l[:unit_type].present?
    }.map { |l|
      ListingViewUtils.translate_unit(l[:unit_type], l[:unit_tr_key])
    }.or_else(nil)
  end

  def translate_selector_label_from_listing(listing)
    Maybe(listing).select { |l|
      l[:unit_type].present?
    }.map { |l|
      ListingViewUtils.translate_quantity(l[:unit_type], l[:unit_selector_tr_key])
    }.or_else(nil)
  end

  def query_person_entity(id)
    person_entity = MarketplaceService::Person::Query.person(id, @current_community.id)
    person_display_entity = person_entity.merge(
      display_name: PersonViewUtils.person_entity_display_name(person_entity, @current_community.name_display_type)
    )
  end

  def create_post_pay_transaction(opts)
    gateway_fields = {}
#      if (opts[:payment_type] == :paypal)
#        # PayPal doesn't like images with cache buster in the URL
#        logo_url = Maybe(opts[:community])
#          .wide_logo
#          .select { |wl| wl.present? }
#          .url(:paypal, timestamp: false)
#          .or_else(nil)
#
#        {
#          merchant_brand_logo_url: logo_url,
#          success_url: success_paypal_service_checkout_orders_url,
#          cancel_url: cancel_paypal_service_checkout_orders_url(listing_id: opts[:listing].id)
#        }
#      else
#        BraintreeForm.new(opts[:bt_payment_params]).to_hash
#      end

    transaction = {
          community_id: opts[:community].id,
          listing_id: opts[:listing].id,
          listing_title: opts[:listing].title,
          starter_id: opts[:user].id,
          listing_author_id: opts[:listing].author.id,
          listing_quantity: opts[:listing_quantity],
          unit_type: opts[:listing].unit_type,
          unit_price: opts[:listing].price,
          unit_tr_key: opts[:listing].unit_tr_key,
          unit_selector_tr_key: opts[:listing].unit_selector_tr_key,
          content: opts[:content],
          payment_gateway: opts[:payment_type],
          payment_process: :postpay,
          booking_fields: opts[:booking_fields],
          cart_fields: opts[:cart_fields],
          delivery_method: opts[:delivery_method]
    }

    if(opts[:delivery_method] == :shipping)
      transaction[:shipping_price] = opts[:shipping_price]
    end

    TransactionService::Transaction.create({
        transaction: transaction,
        gateway_fields: gateway_fields,
      },
      paypal_async: opts[:use_async])
  end

  def render_error_response(is_xhr, error_msg, redirect_params)
    if is_xhr
      render json: { error_msg: error_msg }
    else
      flash[:error] = error_msg
      redirect_to(redirect_params)
    end
  end

  def ensure_listing_author_is_not_current_user
    if @listing.author == @current_user
      flash[:error] = t("layouts.notifications.you_cannot_send_message_to_yourself")
      redirect_to (session[:return_to_content] || search_path)
    end
  end

  # Ensure that only users with appropriate visibility settings can reply to the listing
  def ensure_authorized_to_reply
    unless @listing.visible_to?(@current_user, @current_community)
      flash[:error] = t("layouts.notifications.you_are_not_authorized_to_view_this_content")
      redirect_to search_path and return
    end
  end

  def ensure_listing_is_open
    if @listing.closed?
      flash[:error] = t("layouts.notifications.you_cannot_reply_to_a_closed_offer")
      redirect_to (session[:return_to_content] || search_path)
    end
  end

  def fetch_listing_from_params
    @listing = Listing.find(params[:listing_id] || params[:id])
  end

  def new_contact_form(conversation_params = {})
    ContactForm.new(conversation_params.merge({sender_id: @current_user.id, listing_id: @listing.id, community_id: @current_community.id}))
  end

  def ensure_can_receive_payment
    Maybe(@current_community).payment_gateway.each do |gateway|
      unless gateway.can_receive_payments?(@listing.author)
        flash[:error] = t("layouts.notifications.listing_author_payment_details_missing")
        redirect_to (session[:return_to_content] || search_path)
      end
    end
  end
end
