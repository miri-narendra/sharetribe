module TransactionService::Gateway
  class StripeAdapter < GatewayAdapter

    PaymentModel = ::Payment

    def implements_process(process)
      [:preauthorize, :postpay].include?(process)
    end

    def create_payment(tx:, gateway_fields:, prefer_async: nil)
      #INFO this is called only from TransactionService::Process::Preauthorize
      # PostPay triggers payments differently
      payment_gateway_id = StripePaymentGateway.where(community_id: tx[:community_id]).pluck(:id).first
      payment_schedule = TransactionService::PaymentSchedule.get(community_id: tx[:community_id], transaction_id: tx[:id])
      payment = StripePayment.where(transaction_id: tx[:id]).first
      payment ||= StripePayment.create(
        {
          transaction_id: tx[:id],
          community_id: tx[:community_id],
          payment_gateway_id: payment_gateway_id,
          status: :pending,
          payer_id: tx[:starter_id],
          recipient_id: tx[:listing_author_id],
          currency: "USD",
          sum: payment_schedule.total_with_security_deposit_sum,
          commission: payment_schedule.total_commission
        } )

      payment_schedule.payment = payment
      split_payment = payment.next_pending_split

      PAYMENT_EVENT_LOG.info("Start creating payment for transaction #{tx[:id]}")
      result = StripeSaleService.new(payment, gateway_fields).pay

      if result['paid']
        SyncCompletion.new(Result::Success.new({result: true}))
      else
        SyncCompletion.new(Result::Error.new(result['error'].message))
      end
    end

    def reject_payment(tx:, reason: nil)
      result = StripeService::Payments::Command.void_transaction(tx[:id], tx[:community_id])

      if result.success?
        SyncCompletion.new(Result::Success.new({result: true}))
      else
        SyncCompletion.new(Result::Error.new(result.message))
      end
    end

    #def complete_preauthorization(tx:)
    #  #result = BraintreeService::Payments::Command.submit_to_settlement(tx[:id], tx[:community_id])

    #  if !result.success?
    #    SyncCompletion.new(Result::Error.new(result.message))
    #  end

    #  SyncCompletion.new(Result::Success.new({result: true}))
    #end

    def get_payment_details(tx:)
      payment_total = Maybe(PaymentModel.where(transaction_id: tx[:id]).first).total_sum.or_else(nil)
      total_price = tx[:unit_price] * tx[:listing_quantity]
      { payment_total: payment_total,
        total_price: total_price,
        charged_commission: nil,
        payment_gateway_fee: nil }
    end

  end
end
