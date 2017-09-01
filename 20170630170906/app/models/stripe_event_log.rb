# == Schema Information
#
# Table name: stripe_event_logs
#
#  id             :integer          not null, primary key
#  transaction_id :integer
#  event_type     :string(255)
#  event_message  :text(65535)
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#

class StripeEventLog < ActiveRecord::Base
  belongs_to :tx, class_name: "Transaction", foreign_key: "transaction_id"

  attr_accessible :transaction_id,
    :event_type,
    :event_message
end
