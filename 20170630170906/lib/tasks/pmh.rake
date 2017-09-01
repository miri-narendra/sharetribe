namespace :pmh do
  namespace :admin_notifications do
    desc "Inform admin which transactions are pending and inactive for 5 days"
    task :stuck_transactions => :environment do |t, args|
      pmh_community_id = 16328
      Delayed::Job.enqueue(TransactionsStuckAdminNotificationJob.new(pmh_community_id))
    end
  end

  namespace :admin_notifications do
    desc "Inform admin which transactions are accepted to pay but not fully paid for within 5 days from the scheduled payment date"
    task :stuck_scheduled_payments => :environment do |t, args|
      pmh_community_id = 16328
      Delayed::Job.enqueue(ScheduledPaymentsStuckAdminNotificationJob.new(pmh_community_id))
    end
  end

  namespace :admin_notifications do
    desc "Inform admin about all current owners not linked with Stripe"
    task :stripe_not_linked => :environment do |t, args|
      pmh_community_id = 16328
      Delayed::Job.enqueue(NotifyStripeNotLinkedJob.new(pmh_community_id))
    end
  end

  namespace :renter_notifications do
    desc "Inform the renters about pending transactions"
    task :stuck_transactions => :environment do |t, args|
      pmh_community_id = 16328
      Delayed::Job.enqueue(TransactionsStuckRenterNotificationJob.new(pmh_community_id))
    end
  end

  namespace :payments do
    desc "Perform automatic payments"
    task :process_pending => :environment do |t, args|
      pmh_community_id = 16328
      Delayed::Job.enqueue(PendingPaymentsProcessingJob.new(pmh_community_id, Date.today))
    end
  end

  namespace :renter_notifications do
    desc "Inform the renters and admins about not refunded deposits"
    task :not_refunded_deposits => :environment do |t, args|
      pmh_community_id = 16328
      Delayed::Job.enqueue(NotRefundedDepositsNotificationsJob.new(pmh_community_id))
    end
  end
end
