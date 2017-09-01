class RefundConversationsController < ApplicationController

  before_filter do |controller|
    controller.ensure_logged_in t("layouts.notifications.you_must_log_in_to_accept_or_reject")
  end

  before_filter :fetch_conversation
  before_filter :fetch_listing

  before_filter :ensure_is_author
  before_filter :ensure_stripe_is_connected

  # Skip auth token check as current jQuery doesn't provide it automatically
  skip_before_filter :verify_authenticity_token

  MessageForm = Form::Message

  def full_refund
    prepare_refund_form
    @action = "full_refund"
    path_to_payment_settings = payment_settings_path(@current_community.payment_gateway.gateway_type, @current_user)
    render(:refund, locals: { path_to_payment_settings: path_to_payment_settings, message_form: MessageForm.new })
  end

  def partial_refund
    prepare_refund_form
    @action = "partial_refund"
    path_to_payment_settings = payment_settings_path(@current_community.payment_gateway.gateway_type, @current_user)
    render(:refund, locals: { path_to_payment_settings: path_to_payment_settings, message_form: MessageForm.new })
  end

  def refund_and_cancel
    prepare_refund_form
    @action = "full_refund"
    @do_cancel = "cancel_with_refund"
    path_to_payment_settings = payment_settings_path(@current_community.payment_gateway.gateway_type, @current_user)
    render(:refund, locals: { path_to_payment_settings: path_to_payment_settings, message_form: MessageForm.new })
  end

  def refund
    message = MessageForm.new(params[:message].merge({ conversation_id: @listing_conversation.id }))
    if message.valid?
      @listing_conversation.conversation.messages.create({content: message.content}.merge(sender_id: @current_user.id))
    end
    
    if params[:do_cancel] == 'cancel_with_refund'
      notice = refund_payments_and_cancel
    else
      notice = refund_security_deposit
    end

    unless notice == false
      flash[:notice] = notice
      redirect_to person_transaction_path(:person_id => @current_user.id, :id => @listing_conversation.id)
    end
  end

  private

  def prepare_refund_form
    @payment_schedule = TransactionService::PaymentSchedule.get(community_id: @current_community.id, transaction_id: @listing_conversation.id)
    @security_split = @payment_schedule.security_payment_split
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

  def fetch_listing
    @listing = @listing_conversation.listing
  end

  def fetch_conversation
    @listing_conversation = Transaction.find(params[:id])
  end

  def refund_security_deposit
    payment_schedule = TransactionService::PaymentSchedule.get(community_id: @current_community.id, transaction_id: @listing_conversation.id)
    security_split = payment_schedule.security_payment_split

    return nil unless security_split

    if params[:refund_action] == 'partial_refund'
      refund_total = Money.new(params[:refund_sum].to_f*100, @listing_conversation.unit_price_currency) 
    else
      refund_total = payment_schedule.security_deposit_sum
    end

    if refund_total <= 0 || refund_total > payment_schedule.security_deposit_sum || security_split.nil?
      flash[:error] = t("layouts.notifications.invalid_refund_sum")
      redirect_to person_transaction_path(:person_id => @current_user.id, :id => @listing_conversation.id)
      return false
    end

    result = StripeRefundService.new(security_split, refund_total).refund
    if result['status'] == 'succeeded'
      message = I18n.t("layouts.notifications.refunded_success", amount: refund_total.format)
      @listing_conversation.conversation.messages.create(content: message, sender_id: @current_user.id)
    else
      message = I18n.t("layouts.notifications.refunded_error", amount: refund_total.format, error: result['error'].to_s)
      @listing_conversation.conversation.messages.create(content: message, sender_id: @current_user.id)
    end
    message
  end

  def refund_payments_and_cancel
    payment_schedule = TransactionService::PaymentSchedule.get(community_id: @current_community.id, transaction_id: @listing_conversation.id)

    full_refund_sum = payment_schedule.paid_sum - payment_schedule.paid_commission
    if params[:refund_action] == 'partial_refund'
      refund_total = Money.new(params[:refund_sum].to_f*100, @listing_conversation.unit_price_currency) 
    elsif params[:refund_action] == 'no_refund'
      refund_total = Money.new(0, @listing_conversation.unit_price_currency)
    else
      refund_total = full_refund_sum
    end

    if refund_total < 0 || refund_total > full_refund_sum
      flash[:error] = t("layouts.notifications.invalid_refund_sum")
      redirect_to person_transaction_path(:person_id => @current_user.id, :id => @listing_conversation.id)
      return false
    end

    paid_splits = payment_schedule.paid_splits.to_a

    paid_splits.each do |payment_split|
      to_refund = [payment_split.sum - payment_split.commission, refund_total].min
      next if to_refund == 0
      result = StripeRefundService.new(payment_split, to_refund).refund
      if result['status'] == 'succeeded'
        message = I18n.t("layouts.notifications.refunded_success", amount: to_refund.format)
        @listing_conversation.conversation.messages.create(content: message, sender_id: @current_user.id)
      else
        message = I18n.t("layouts.notifications.refunded_error", amount: to_refund.format, error: result['error'].to_s)
        @listing_conversation.conversation.messages.create(content: message, sender_id: @current_user.id)
        break
      end
      refund_total -= to_refund
    end

    TransactionService::Transaction.cancel(community_id: @listing_conversation.community_id, transaction_id: @listing_conversation.id, message: '', sender_id: @current_user.id)
    flash[:notice] = t("layouts.notifications.offer_canceled")
  end

end
