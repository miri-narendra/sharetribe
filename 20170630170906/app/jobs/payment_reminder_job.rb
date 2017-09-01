# conversation_id should be transaction_id, but hard to migrate due to existing job descriptions in DB
class PaymentReminderJob < Struct.new(:conversation_id, :recipient_id, :community_id, :template)

  include DelayedAirbrakeNotification

  # This before hook should be included in all Jobs to make sure that the service_name is
  # correct as it's stored in the thread and the same thread handles many different communities
  # if the job doesn't have community_id parameter, should call the method with nil, to set the default service_name
  def before(job)
    # Set the correct service name to thread for I18n to pick it
    ApplicationHelper.store_community_service_name_to_thread_from_community_id(community_id)
  end

  def perform
    transaction = Transaction.find(conversation_id)
    community = Community.find(community_id)
    can_transition_to_paid = MarketplaceService::Transaction::Query.can_transition_to?(transaction.id, :paid)
    payment_schedule = TransactionService::PaymentSchedule.get(community_id: community_id, transaction_id: conversation_id)

    if can_transition_to_paid && (payment_schedule.due_sum_in(3) > 0)
      MailCarrier.deliver_now(PersonMailer.send("payment_reminder", transaction, transaction.payment.payer, community, template))
    end
  end

end
