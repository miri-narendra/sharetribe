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

class BraintreePayment < Payment
  attr_accessible :braintree_transaction_id, :currency, :sum, :commission

  monetize :sum_cents, allow_nil: true, with_model_currency: :currency
  monetize :commission_cents, allow_nil: true, with_model_currency: :currency

  def sum_exists?
    !sum_cents.nil?
  end

  def total_sum
    sum
  end

  # Build default payment sum by transaction
  # Note: Consider removing this :(
  def default_sum(transaction_hash, vat=0)
    self.sum = transaction_hash[:checkout_total] || transaction_hash[:item_total] || transaction_hash[:listing_price]
  end
end
