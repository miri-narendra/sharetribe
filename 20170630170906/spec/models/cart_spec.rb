# == Schema Information
#
# Table name: carts
#
#  id                                    :integer          not null, primary key
#  community_id                          :integer
#  transaction_id                        :integer
#  pickup_location                       :string(255)
#  dropoff_location                      :string(255)
#  housekeeping_kit                      :boolean
#  created_at                            :datetime         not null
#  updated_at                            :datetime         not null
#  currency                              :string(255)
#  additional_miles_price_per_mile_cents :integer
#  generator_hours_price_per_hour_cents  :integer
#  cleaning_fee_cents                    :integer
#  housekeeping_kit_price_cents          :integer
#  dump_water_fee_cents                  :integer
#  security_deposit_cents                :integer
#  delivery_fee_per_mile                 :string(255)
#  cancellation_policy                   :string(255)
#  minimum_duration                      :integer
#  additional_miles                      :integer
#  additional_generator_hours            :integer
#  pickup_dropoff_fee_cents              :integer
#  included_miles_per_day                :integer
#  included_generator_hours_per_day      :integer
#  discount_cents                        :integer          default(0)
#

require 'rails_helper'

RSpec.describe Cart, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
