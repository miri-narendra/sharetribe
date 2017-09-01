# conversation_id should be transaction_id, but hard to migrate due to existing job descriptions in DB
class PendingPaymentsProcessingJob < Struct.new(:community_id, :due_date)

  include DelayedAirbrakeNotification

  # This before hook should be included in all Jobs to make sure that the service_name is
  # correct as it's stored in the thread and the same thread handles many different communities
  # if the job doesn't have community_id parameter, should call the method with nil, to set the default service_name
  def before(job)
    # Set the correct service name to thread for I18n to pick it
    ApplicationHelper.store_community_service_name_to_thread_from_community_id(community_id)
  end

  def perform
    payment_splits = PaymentSplit.joins(:payment).where(:payments => {:community_id =>  community_id}).where(:status => 'pending', :due_on => due_date).all
    payment_splits.each do |payment_split|
      attempt_payment(payment_split)
    end
  end

  def attempt_payment(payment_split)
    payment = payment_split.payment
    tx = payment.tx
    
    # skip not accepted transactions
    return unless tx.current_state == 'accepted' || tx.current_state == 'paid'
    
    # skip recipients w/o stripe account
    return unless payment.recipient.stripe_account && payment.recipient.stripe_account.stripe_user_id.present?
    
    # skip payers w/o stored cards
    return unless payment.payer.stripe_account && payment.payer.stripe_account.has_stored_card?

    sale_service = StripeSaleService.new(payment_split, {:storedCard => true})
    result = sale_service.pay
    PAYMENT_EVENT_LOG.info("PendingPaymentsProcessingJob for transaction #{tx.id}, PaymentSplit #{payment_split.id} Result: #{result.inspect}")
    return unless result['paid'] 

    # update payment and txn status -- same logic as app/controllers/stripe_payments_controller.rb
    payment.paid!
    payment.reload
    
    if payment.status == 'partial'
      tx.payment_status = Transaction::PARTIALLY_PAID
    elsif payment.status == 'paid'
      if payment.payment_splits.pending.count > 0
        tx.payment_status = Transaction::PAID
      else
        tx.payment_status = Transaction::PAID_INCLUDING_DEPOSIT
      end
    end
    tx.save

    if tx.payment_status == Transaction::PAID
      MarketplaceService::Transaction::Command.transition_to(tx.id, 'paid')
    end
    Delayed::Job.enqueue(PaymentSplitSuccessJob.new(payment.id, tx.id, tx.community_id))
  rescue => ex
    Rails.logger.error("Exception: #{ex.inspect}")
    Rails.logger.error(ex.backtrace.join("\n"))
  end

end
