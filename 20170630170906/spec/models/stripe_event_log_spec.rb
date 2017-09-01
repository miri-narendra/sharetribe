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

require 'rails_helper'

RSpec.describe StripeEventLog, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
