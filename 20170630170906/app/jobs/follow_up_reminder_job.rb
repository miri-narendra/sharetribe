class FollowUpReminderJob < Struct.new(:transaction_id, :community_id, :template)

  include DelayedAirbrakeNotification

  # This before hook should be included in all Jobs to make sure that the service_name is
  # correct as it's stored in the thread and the same thread handles many different communities
  # if the job doesn't have community_id parameter, should call the method with nil, to set the default service_name
  def before(job)
    # Set the correct service name to thread for I18n to pick it
    ApplicationHelper.store_community_service_name_to_thread_from_community_id(community_id)
  end

  def perform
    transaction = Transaction.find(transaction_id)
    community = Community.find(community_id)
    can_transition_to_paid = MarketplaceService::Transaction::Query.can_transition_to?(transaction.id, :paid)
    payment_schedule = TransactionService::PaymentSchedule.get(community_id: community.id, transaction_id: transaction.id)

    if can_transition_to_paid && (payment_schedule.due_sum_in(0) > 0)
      MailCarrier.deliver_now(PersonMailer.send("follow_up_reminder", transaction, template))
    end
  end

end
