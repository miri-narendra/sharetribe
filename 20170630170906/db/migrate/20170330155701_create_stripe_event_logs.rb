class CreateStripeEventLogs < ActiveRecord::Migration
  def change
    create_table :stripe_event_logs do |t|
      t.integer  :transaction_id
      t.string :event_type
      t.text :event_message

      t.timestamps null: false
    end
  end
end
