class AutomaticOfferCancelingJob < Struct.new(:offer_id, :community_id)

  include DelayedAirbrakeNotification

  # This before hook should be included in all Jobs to make sure that the service_name is
  # correct as it's stored in the thread and the same thread handles many different communities
  # if the job doesn't have host parameter, should call the method with nil, to set the default service_name
  def before(job)
    # Set the correct service name to thread for I18n to pick it
    ApplicationHelper.store_community_service_name_to_thread_from_community_id(community_id)
  end

  def perform
    offer = Transaction.find(offer_id)
    community = Community.find(community_id)
    can_transition_to_canceled = MarketplaceService::Transaction::Query.can_transition_to?(offer.id, :canceled)
    payment_schedule = TransactionService::PaymentSchedule.get(community_id: community.id, transaction_id: offer.id)

    if can_transition_to_canceled && payment_schedule.has_paid_nothing_yet?
      MarketplaceService::Transaction::Command.transition_to(offer.id, :canceled)
    end
  end

end
