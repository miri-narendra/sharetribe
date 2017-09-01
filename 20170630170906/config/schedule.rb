every :day, at: '6am' do
  rake 'sharetribe:community_updates:deliver'
  rake 'pmh:payments:process_pending'
  rake 'pmh:admin_notifications:stuck_transactions'
  rake 'pmh:admin_notifications:stuck_scheduled_payments'
  rake 'pmh:renter_notifications:stuck_transactions'
  rake 'pmh:renter_notifications:not_refunded_deposits'
end

every :sunday, :at => '12pm' do
  rake 'pmh:admin_notifications:stripe_not_linked'
end
