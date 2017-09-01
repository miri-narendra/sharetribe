class StripeRefundService
  def initialize(payment_split, total)
    @payment_split = payment_split
    @payment = payment_split.payment
    @community = @payment.community
    @payer = @payment.payer
    @recipient = @payment.recipient
    @amount = total.cents
  end

  def refund
    result = call_stripe_api

    if result['status'] == 'succeeded'
      save_transaction_id!(result)
    end
    log_result(result)

    result
  end

  private

  def call_stripe_api
    with_exception_logging do
      StripeLog.warn("Refunding to #{@payer.id} from #{@recipient.id}. Amount: #{@amount}")
      StripeApi.refund(@community, @payment_split.stripe_transaction_id, @amount, @recipient.stripe_account.stripe_user_id)
    end
  end

  def save_transaction_id!(result)
    @payment_split.update_attributes(stripe_refund_id: result["id"], is_refunded: true, refund_cents: @amount)
    @payment.tx.update_attribute(:payment_status, Transaction::PAID_REFUNDED_DEPOSIT)
  end

  def log_result(result)
    if result['status'] == 'succeeded'
      transaction_id = result["id"]
      StripeLog.warn("Successful refund #{transaction_id} to #{@payer.id}.id}. Amount: to #{@amount}")
    else
      StripeLog.warn("Unsuccessful refund to #{@payer.id}.id}. Amount: to #{@amount}")
    end
  end

  def with_exception_logging(&block)
    begin
      block.call
    rescue Exception => e
      StripeLog.error("Exception #{e.inspect} #{e.backtrace.join("\n")}")
      result = {}
      result['status'] = 'failed'
      result['error'] = e.message
      result
    end
  end
end
