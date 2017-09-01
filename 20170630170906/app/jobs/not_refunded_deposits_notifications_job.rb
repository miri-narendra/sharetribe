class NotRefundedDepositsNotificationsJob < Struct.new(:community_id)
  include DelayedAirbrakeNotification

  def before(job)
    # Set the correct service name to thread for I18n to pick it
    ApplicationHelper.store_community_service_name_to_thread_from_community_id(community_id)
  end

  def perform
    community = Community.find(community_id)
    tx_list = Transaction.where(community_id: community_id, current_state: 'confirmed', payment_state: Transaction::PAID_INCLUDING_DEPOSIT).all
    tx_list.each do |tx|
      if (tx.transaction_transitions.last.created_at.to_date + 7) == Date.current
        MailCarrier.deliver_now(PersonMailer.send("deposit_refund_reminder", transaction, transaction.payment.recipient, community))
      end
    end
  end
end
