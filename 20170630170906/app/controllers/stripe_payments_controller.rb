class StripePaymentsController < ApplicationController

  before_filter :fetch_conversation
  before_filter :ensure_not_paid_already
  before_filter :payment_can_be_conducted

  before_filter do |controller|
    controller.ensure_logged_in t("layouts.notifications.you_must_log_in_to_view_your_inbox")
  end

  def edit
    #message/conversation and transaction seem to be used interchangeably here
    recipient = @stripe_payment.recipient
    if recipient.stripe_account.nil? || recipient.stripe_account.stripe_publishable_key.nil?
      payer = @stripe_payment.payer
      StripeEventLog.create!(
          transaction_id: @conversation.id,
          event_type: 'PaymentNoStripeAccount',
          event_message: t("error_messages.stripe.event_log.not_linked_account_error", user_name: payer.full_name, user_email: payer.emails.best_address, owner_name: recipient.full_name, owner_email: recipient.emails.best_address, transaction_id: @conversation.id)
      )
      flash[:error] = t("error_messages.stripe.seller_not_linked_account_error")
      redirect_to person_transaction_url(@current_user, {:id => @conversation.id}) and return
    end
    payment_object = if @stripe_payment.respond_to?(:next_pending_split)
      payment_schedule = TransactionService::PaymentSchedule.get(community_id: @conversation.community_id, transaction_id: @conversation.id)
      payment_schedule.update_pending_payment_splits(pay_upfront: (params[:pay_upfront] == "true"))
      @stripe_payment.next_pending_split
    else
      @stripe_payment
    end
    @sum = payment_object.sum
    render locals: {stripe_form: Form::Stripe.new}
  end

  def update
    #we need to send payment reminders for offers only if the first payment is made
    PAYMENT_EVENT_LOG.info("StripePaymentController#update start for transaction #{@conversation.id}")
    this_is_the_first_payment = !@conversation.payment.first_payment_is_made
    stripe_form = Form::Stripe.new(params)
    transaction_hash = TransactionService::Transaction.get(transaction_id: @conversation.id, community_id: @conversation.community_id).data
    gateway_adapter = TransactionService::Gateway::StripeAdapter.new
    result = gateway_adapter.create_payment(tx: transaction_hash, gateway_fields: stripe_form.to_hash)

    if result.success
      @stripe_payment.reload
      if @stripe_payment.status == 'partial'
        @conversation.payment_status = Transaction::PARTIALLY_PAID
      elsif @stripe_payment.status == 'paid'
        @conversation.payment_status = if @stripe_payment.payment_splits.pending.count > 0 then
          Transaction::PAID
        else
          Transaction::PAID_INCLUDING_DEPOSIT
        end
      end
      @conversation.save
      if @stripe_payment.status == 'paid'
        MarketplaceService::Transaction::Command.transition_to(@conversation.id, 'paid')
      end
      #we need to send payment reminders for offers only if the first payment is made
      if @conversation.is_offer && this_is_the_first_payment
        TransactionService::Transaction.schedule_payment_reminders(@current_community, @conversation, skip_first_reminder: true)
      end
      Delayed::Job.enqueue(PaymentSplitSuccessJob.new(@stripe_payment.id, @conversation.id, @conversation.community_id))
      PAYMENT_EVENT_LOG.info("StripePaymentController#update success for transaction #{@conversation.id}")
      redirect_to person_transaction_path(id: params[:message_id])
    else
      # expecting result to be an exception
      PAYMENT_EVENT_LOG.info("StripePaymentController#update failure for transaction #{@conversation.id}")
      flash[:error] = result.response.error_msg
      redirect_to :edit_person_message_stripe_payment
    end
  end

  private

  def fetch_conversation
    @conversation = Transaction.find(params[:message_id])
    @stripe_payment = @conversation.payment
  end

  def ensure_not_paid_already
    schedule = TransactionService::PaymentSchedule.get(community_id: @conversation.community_id, transaction_id: @conversation.id)
    if schedule.all_payments_paid?
      flash[:error] = 'Could not find pending payment. It might be the payment is paid already.'
      redirect_to person_transaction_path(@current_user, @conversation) and return
    end
  end

  def payment_can_be_conducted
    redirect_to person_transaction_path(@current_user, @conversation) unless @conversation.requires_payment?(@current_community)
  end
end
