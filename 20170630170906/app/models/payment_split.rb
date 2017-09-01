# == Schema Information
#
# Table name: payment_splits
#
#  id                       :integer          not null, primary key
#  payment_id               :integer
#  status                   :string(255)
#  sum_cents                :integer
#  commission_cents         :integer
#  currency                 :string(255)
#  braintree_transaction_id :string(255)
#  created_at               :datetime
#  updated_at               :datetime
#  stripe_transaction_id    :string(255)
#  due_on                   :date
#  paid_on                  :date
#  stripe_refund_id         :string(255)
#  is_refunded              :boolean          default(FALSE)
#  refund_cents             :integer
#
# Indexes
#
#  index_payment_splits_on_due_on      (due_on)
#  index_payment_splits_on_paid_on     (paid_on)
#  index_payment_splits_on_payment_id  (payment_id)
#

class PaymentSplit < ActiveRecord::Base

  include MathHelper

  VALID_STATUSES = ["paid", "pending", "disbursed"]

  attr_accessible :payment_id, :payment, :status, :currency, :sum, :commission,
                  :braintree_transaction_id, :stripe_transaction_id, :due_on,
                  :paid_on, :stripe_refund_id, :is_refunded, :refund_cents

  belongs_to :payment

  monetize :sum_cents, allow_nil: true, with_model_currency: :currency
  monetize :commission_cents, allow_nil: true, with_model_currency: :currency
  monetize :refund_cents, allow_nil: true, with_model_currency: :currency

  validates_inclusion_of :status, :in => VALID_STATUSES
  validate :validate_sum

  delegate :transaction, to: :payment
  delegate :payer, to: :payment
  delegate :recipient, to: :payment
  delegate :community, to: :payment
  delegate :payment_gateway, to: :payment

  scope :paid, -> { where(status: :paid) }
  scope :pending, -> { where(status: :pending) }

  def validate_sum
    unless sum_exists?
      errors.add(:base, "Payment is not valid without sum")
    end
  end

  def sum_exists?
    !sum_cents.nil?
  end

  def paid!
    update_attributes(status: "paid", paid_on: Date.today)
  end

  def disbursed!
    update_attribute(:status, "disbursed")
    # Notification here?
  end

  # alias required for app/services/*_sale_service.rb so that payment and payment splits are interchangeable
  def total_commission
    commission
  end

  def seller_gets
    sum - commission
  end

  def commission_without_vat
    vat = Maybe(community).vat.or_else(0).to_f / 100.to_f
    commission / (1 + vat)
  end
end
