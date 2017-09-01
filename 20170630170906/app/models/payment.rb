# == Schema Information
#
# Table name: payments
#
#  id                       :integer          not null, primary key
#  payer_id                 :string(255)
#  recipient_id             :string(255)
#  organization_id          :string(255)
#  transaction_id           :integer
#  status                   :string(255)
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  community_id             :integer
#  payment_gateway_id       :integer
#  sum_cents                :integer
#  currency                 :string(255)
#  type                     :string(255)      default("CheckoutPayment")
#  braintree_transaction_id :string(255)
#  commission_cents         :integer
#  stripe_transaction_id    :string(255)
#  adjusted_sum_cents       :integer
#  commission_percent       :integer
#
# Indexes
#
#  index_payments_on_conversation_id  (transaction_id)
#  index_payments_on_payer_id         (payer_id)
#

class Payment < ActiveRecord::Base

  include MathHelper

  VALID_STATUSES = ["paid", "partial", "pending", "disbursed"]

  attr_accessible :transaction_id, :conversation_id, :payer_id, :recipient_id, :community_id, :payment_gateway_id, :status

  belongs_to :tx, class_name: "Transaction", foreign_key: "transaction_id"
  belongs_to :payer, :class_name => "Person"
  belongs_to :recipient, :class_name => "Person"

  belongs_to :community
  belongs_to :payment_gateway

  has_many :payment_splits, ->() { order('id') }, class_name: "PaymentSplit", :dependent => :destroy 

  monetize :commission_cents, allow_nil: true, with_model_currency: :currency

  validates_inclusion_of :status, :in => VALID_STATUSES
  validate :validate_sum

  before_save :force_adjusted_sum
  def force_adjusted_sum
    raise "sum is already adjusted" if sum_cents_changed? && adjusted_sum.present? && adjusted_sum != sum
  end

  #make sure we save current commission fee to payment, so that we store historically correct data
  def commission_from_seller
    commission_percent || tx.seller.commission_percent_for(tx.community)
  end

  def security_deposit
    tx.try(:cart).try(:security_deposit) || Money.new(0, 'USD')
  end

  def validate_sum
    unless sum_exists?
      errors.add(:base, "Payment is not valid without sum")
    end
  end

  def paid!
    if is_fully_paid?
      update_attribute(:status, "paid")
    else
      update_attribute(:status, "partial")
    end
  end

  def disbursed!
    update_attribute(:status, "disbursed")
    # Notification here?
  end

  def total_commission_percentage
    Maybe(commission_from_seller).or_else(0).to_f / 100.to_f
  end

  def total_commission
    total_sum * total_commission_percentage
  end

  def seller_gets
    total_sum - total_commission
  end

  def total_commission_without_vat
    vat = Maybe(community).vat.or_else(0).to_f / 100.to_f
    total_commission / (1 + vat)
  end

  def payment_split_sum
    payment_splits.where(status: :paid).inject(Money.new(0, 'USD')){|memo, split| memo += split.sum }
  end

  def is_fully_paid?
    payment_split_sum >= total_sum
  end

  def last_paid_split
    payment_splits.paid.order('due_on').last
  end

  def next_pending_split
    payment_splits.pending.order('due_on').first
  end

  def first_payment_is_made
    payment_splits.paid.count > 0
  end
end
