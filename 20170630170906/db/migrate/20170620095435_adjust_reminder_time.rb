class AdjustReminderTime < ActiveRecord::Migration
  def change
    ActiveRecord::Base.connection.execute "UPDATE delayed_jobs SET run_at = DATE_ADD(CAST(run_at AS DATE), INTERVAL 13 HOUR) WHERE handler LIKE '%PaymentReminderJob%'"
  end
end
