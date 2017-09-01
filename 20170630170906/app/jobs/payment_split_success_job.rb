# conversation_id should be transaction_id, but hard to migrate due to existing job descriptions in DB
class PaymentSplitSuccessJob < Struct.new(:payment_id, :transaction_id, :community_id)

  include DelayedAirbrakeNotification

  # This before hook should be included in all Jobs to make sure that the service_name is
  # correct as it's stored in the thread and the same thread handles many different communities
  # if the job doesn't have community_id parameter, should call the method with nil, to set the default service_name
  def before(job)
    # Set the correct service name to thread for I18n to pick it
    ApplicationHelper.store_community_service_name_to_thread_from_community_id(community_id)
  end

  def perform
    community = Community.find(community_id)
    transaction = Transaction.find(transaction_id)
    payment = Payment.find(payment_id)

    MailCarrier.deliver_now(PersonMailer.send("new_payment_split_owner", payment, transaction, community))
    MailCarrier.deliver_now(PersonMailer.send("new_payment_split_renter", payment, transaction, community))
    admin_notification_mail = PersonMailer.send("new_payment_notification", payment, transaction, community)
    PAYMENT_EVENT_LOG.info("new_payment_notification email for transaction: #{transaction.id} with MessageID #{admin_notification_mail.message_id} sent")
    MailCarrier.deliver_now(admin_notification_mail)
  end

end
