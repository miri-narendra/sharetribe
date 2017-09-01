class StripeSaleService
  def initialize(payment, payment_params)
    subunit_to_unit = Money::Currency.new(payment.currency).subunit_to_unit

    @payment = payment
    @community = payment.community
    @payer = payment.payer
    @recipient = payment.recipient
    @payment_object = if @payment.respond_to?(:next_pending_split)
      @payment_split = @payment.next_pending_split
    else
      @payment
    end
    @amount = @payment_object.sum.cents
    @service_fee = @payment_object.total_commission.cents
    @params = payment_params || {}
  end

  def pay
    result = call_stripe_api

    if result['paid']
      save_transaction_id!(result)
      change_payment_status_to_paid!
    end

    log_result(result)

    result
  end

  private

  def call_stripe_api
    with_exception_logging do
      StripeLog.warn("Sending sale transaction from #{@payer.id} to #{@recipient.id}. Amount: #{@payment.sum.to_f}, fee: #{@payment.total_commission.to_f}")

      if @params[:stripeToken].present?
        if !@payer.stripe_account
          @payer.create_stripe_account(community_id: @community.id)
        end
        if @payer.stripe_account.stripe_customer_id.present?
          customer = StripeApi.update_customer(@community, @payer.stripe_account.stripe_customer_id, @params[:stripeToken])
        else
          customer = StripeApi.register_customer(@community, @params[:stripeEmail], @params[:stripeToken])
          @payer.stripe_account.update_attribute(:stripe_customer_id, customer.id)
        end
        card_info = get_card_info(customer)
        @payer.stripe_account.update_attribute(:stripe_source_info, card_info)
      end

      customer_id = @payer.stripe_account.stripe_customer_id
      
      stripe_token = StripeApi.create_token(@community, customer_id,  @recipient.stripe_account.stripe_user_id)
      token_id = stripe_token.id

      StripeApi.charge(@community, {
          source:      token_id,
          amount:      @amount,
          #TODO VP Add description in locales?
          description: "Purchase via PrivateMotorHomeRental.com Payment ##{@payment_object.id}",
          currency:    @payment_object.sum.currency.iso_code.downcase,
          application_fee: @service_fee
        },
        {
          stripe_account: @recipient.stripe_account.stripe_user_id
        }
      )
    end

  end

  def save_transaction_id!(result)
    @payment_object.update_attributes(stripe_transaction_id: result["id"])
  end

  def change_payment_status_to_paid!
    @payment_split.paid! if @payment_split
    @payment.paid!
  end

  def log_result(result)
    if result['status'] == 'succeeded'
      transaction_id = result["id"]
      StripeLog.warn("Successful sale transaction #{transaction_id} from #{@payer.id}.id}. Amount: #{@payment.sum.to_f}, fee: #{@payment.total_commission.to_f}")
    else
      StripeLog.error("Unsuccessful sale transaction from #{@payer.id}. Amount: #{@payment.sum.to_f}, fee: #{@payment.total_commission.to_f}: #{result['status']} | #{result['error']}")
    end
  end

  def with_exception_logging(&block)
    begin
      block.call
    rescue Exception => e
      StripeLog.error("Exception #{e.inspect} #{e.backtrace.join("\n")}")
      result = {}
      result['status'] = 'failed'
      result['error'] = e
      result
    end
  end

  def get_card_info customer
    default_id = customer.default_source
    customer.sources.data.each do |source|
      if source.id == default_id && source.object == 'card'
        return [source.brand, "****#{source.last4}", "Exp.#{source.exp_month}/#{source.exp_year}"].join(" ")
      end
    end
    return nil
  end
end
