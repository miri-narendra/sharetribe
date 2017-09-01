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

class Cart < ActiveRecord::Base
  belongs_to :tx, class_name: "Transaction", foreign_key: "transaction_id"
  has_many :other_fees
  monetize :additional_miles_price_per_mile_cents,
           :generator_hours_price_per_hour_cents,
           :cleaning_fee_cents,
           :housekeeping_kit_price_cents,
           :dump_water_fee_cents,
           :pickup_dropoff_fee_cents,
           :security_deposit_cents,
           :discount_cents

  accepts_nested_attributes_for :other_fees,
                                allow_destroy: true,
                                reject_if: lambda {|attributes|
                                  attributes[:name].blank? || attributes[:amount_cents].blank?
                                }

  after_save :update_payment

  def total_sum
    (tx.unit_price * tx.listing_quantity) + cart_sum if tx
  end

  def cart_sum
    sum = Money.new(0, Money.default_currency)
    sum += (additional_miles * additional_miles_price_per_mile) if additional_miles
    sum += (additional_generator_hours * generator_hours_price_per_hour) if additional_generator_hours
    #sum += cleaning_fee
    sum += housekeeping_kit_price if housekeeping_kit && housekeeping_kit_price.present?
    #sum += dump_water_fee if dump_water_fee
    sum += pickup_dropoff_fee if pickup_dropoff_fee
    # this is the safe approach - works even if some data have not been persisted
    sum += other_fees.inject(Money.new(0, Money.default_currency)){|memo, value| memo + value.amount}
    sum -= discount if discount
    #NOTE security_deposit should not be added to cart sum - it is not added to payment's total_sum
    sum
  end

  def update_payment
    payment = tx.payment if tx
    if payment && payment.adjusted_sum.nil?
      payment.sum = self.total_sum
      payment.save
    end
  end

  def allow_pickup_dropoff_fee?
    pickup_location.present? || dropoff_location.present?
  end

  def to_hash
    fields_for_hash = [
      :pickup_location,
      :dropoff_location,
      :housekeeping_kit,
      :additional_miles_price_per_mile,
      :generator_hours_price_per_hour,
      :cleaning_fee,
      :housekeeping_kit_price,
      :dump_water_fee,
      :security_deposit,
      :delivery_fee_per_mile,
      :cancellation_policy,
      :minimum_duration,
      :additional_miles,
      :additional_generator_hours,
      :pickup_dropoff_fee,
      :included_miles_per_day,
      :included_generator_hours_per_day,
    ]

    fields_for_hash.inject({}) do |memo, key|
      memo[key] = self.send(key)
      memo
    end
  end
end
