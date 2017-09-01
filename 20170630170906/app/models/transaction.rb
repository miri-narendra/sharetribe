# == Schema Information
#
# Table name: transactions
#
#  id                                :integer          not null, primary key
#  starter_id                        :string(255)      not null
#  listing_id                        :integer          not null
#  conversation_id                   :integer
#  automatic_confirmation_after_days :integer          not null
#  community_id                      :integer          not null
#  created_at                        :datetime         not null
#  updated_at                        :datetime         not null
#  starter_skipped_feedback          :boolean          default(FALSE)
#  author_skipped_feedback           :boolean          default(FALSE)
#  last_transition_at                :datetime
#  current_state                     :string(255)
#  payment_status                    :string(255)      default("not_paid")
#  commission_from_seller            :integer
#  minimum_commission_cents          :integer          default(0)
#  minimum_commission_currency       :string(255)
#  payment_gateway                   :string(255)      default("none"), not null
#  listing_quantity                  :integer          default(1)
#  listing_author_id                 :string(255)
#  listing_title                     :string(255)
#  unit_type                         :string(32)
#  unit_price_cents                  :integer
#  unit_price_currency               :string(8)
#  unit_tr_key                       :string(64)
#  unit_selector_tr_key              :string(64)
#  payment_process                   :string(31)       default("none")
#  delivery_method                   :string(31)       default("none")
#  shipping_price_cents              :integer
#  deleted                           :boolean          default(FALSE)
#  is_offer                          :boolean
#
# Indexes
#
#  index_transactions_on_community_id        (community_id)
#  index_transactions_on_conversation_id     (conversation_id)
#  index_transactions_on_deleted             (deleted)
#  index_transactions_on_last_transition_at  (last_transition_at)
#  index_transactions_on_listing_id          (listing_id)
#  transactions_on_cid_and_deleted           (community_id,deleted)
#

class Transaction < ActiveRecord::Base
  attr_accessible(
    :community_id,
    :starter_id,
    :listing_id,
    :automatic_confirmation_after_days,
    :author_skipped_feedback,
    :starter_skipped_feedback,
    :payment_attributes,
    :payment_gateway,
    :payment_process,
    :commission_from_seller,
    :minimum_commission,
    :listing_quantity,
    :listing_title,
    :listing_author_id,
    :unit_type,
    :unit_price,
    :unit_tr_key,
    :unit_selector_tr_key,
    :shipping_price,
    :delivery_method,
    :is_offer,
    :payment_status
  )

  VALID_PAYMENT_STATUSES = [
      NOT_PAID = 'not_paid'.freeze,
      PARTIALLY_PAID = 'partially_paid'.freeze,
      PAID = 'paid'.freeze,
      PAID_INCLUDING_DEPOSIT = 'paid_including_deposit'.freeze,
      PAID_REFUNDED_DEPOSIT = 'paid_refunded_deposit'.freeze,
  ].freeze

  attr_accessor :contract_agreed

  belongs_to :community
  belongs_to :listing
  has_many :transaction_transitions, dependent: :destroy, foreign_key: :transaction_id
  has_one :payment, foreign_key: :transaction_id
  has_one :cart
  has_one :booking, :dependent => :destroy
  has_one :shipping_address, dependent: :destroy
  belongs_to :starter, :class_name => "Person", :foreign_key => "starter_id"
  belongs_to :conversation
  has_many :testimonials

  delegate :author, to: :listing
  delegate :title, to: :listing, prefix: true

  accepts_nested_attributes_for :booking
  accepts_nested_attributes_for :cart

  validates_presence_of :payment_gateway
  validates_inclusion_of :payment_status, :in => VALID_PAYMENT_STATUSES

  monetize :minimum_commission_cents, with_model_currency: :minimum_commission_currency
  monetize :unit_price_cents, with_model_currency: :unit_price_currency
  monetize :shipping_price_cents, allow_nil: true, with_model_currency: :unit_price_currency

  scope :for_person, -> (person){
    joins(:listing)
    .where("listings.author_id = ? OR starter_id = ?", person.id, person.id)
  }

  def status
    current_state
  end

  def payment_attributes=(attributes)
    payment = initialize_payment

    if attributes[:sum]
      # Simple payment form
      initialize_braintree_payment!(payment, attributes[:sum], attributes[:currency])
    elsif attributes[:payment_rows].present?
      # Complex (multi-row) payment form
      initialize_checkout_payment!(payment, attributes[:payment_rows])
    else
      # Simple payment form
      initialize_stripe_payment!(payment, attributes[:adjusted_sum], attributes[:currency])
    end

    payment.save!
  end

  # TODO Remove this
  def initialize_payment
    payment ||= community.payment_gateway.new_payment
    payment.payment_gateway ||= community.payment_gateway
    payment.tx = self
    payment.status = "pending"
    payment.payer = starter
    payment.recipient = author
    payment.community = community
    payment.commission_percent = payment.commission_from_seller
    payment
  end

  def initialize_braintree_payment!(payment, sum, currency)
    payment.sum = MoneyUtil.parse_str_to_money(sum.to_s, currency)
  end

  def initialize_stripe_payment!(payment, adjusted_sum, currency)
    if adjusted_sum.present?
      payment.adjusted_sum = MoneyUtil.parse_str_to_money(adjusted_sum.to_s, currency)
      payment.sum = payment.adjusted_sum
    else
      transaction_hash = TransactionService::Transaction.get(transaction_id: payment.transaction_id, community_id: payment.community_id).data
      payment.default_sum(transaction_hash, Maybe(@current_community).vat.or_else(0))
      payment.adjusted_sum = payment.sum
    end
  end

  def initialize_checkout_payment!(payment, rows)
    rows.each { |row| payment.rows.build(row.merge(:currency => "EUR")) unless row["title"].blank? } if rows.present?
  end

  def has_feedback_from?(person)
    if author == person
      testimonial_from_author.present?
    else
      testimonial_from_starter.present?
    end
  end

  def feedback_skipped_by?(person)
    if author == person
      author_skipped_feedback?
    else
      starter_skipped_feedback?
    end
  end

  def testimonial_from_author
    testimonials.find { |testimonial| testimonial.author_id == author.id }
  end

  def testimonial_from_starter
    testimonials.find { |testimonial| testimonial.author_id == starter.id }
  end

  # TODO This assumes that author is seller (which is true for all offers, sell, give, rent, etc.)
  # Change it so that it looks for TransactionProcess.author_is_seller
  def seller
    author
  end

  # TODO This assumes that author is seller (which is true for all offers, sell, give, rent, etc.)
  # Change it so that it looks for TransactionProcess.author_is_seller
  def buyer
    starter
  end

  def participations
    [author, starter]
  end

  def payer
    starter
  end

  def payment_receiver
    author
  end

  # If payment through Sharetribe is required to
  # complete the transaction, return true, whether the payment
  # has been conducted yet or not.
  def requires_payment?(community)
    listing.payment_required_at?(community)
  end

  # Return true if the next required action is the payment
  def waiting_payment?(community)
    requires_payment?(community) && status.eql?("accepted")
  end

  # Return true if the transaction is in a state that it can be confirmed
  def can_be_confirmed?
    # TODO This is a lazy fix. Remove this method, and make the caller to use the service directly
    # Models should not know anything about services
    MarketplaceService::Transaction::Query.can_transition_to?(self.id, :confirmed)
  end

  # Return true if the transaction is in a state that it can be canceled
  def can_be_canceled?
    # TODO This is a lazy fix. Remove this method, and make the caller to use the service directly
    # Models should not know anything about services
    MarketplaceService::Transaction::Query.can_transition_to?(self.id, :canceled)
  end

  def with_type(&block)
    block.call(:listing_conversation)
  end

  def latest_activity
    (transaction_transitions + conversation.messages).max
  end

  # Give person (starter or listing author) and get back the other
  #
  # Note: I'm not sure whether we want to have this method or not but at least it makes refactoring easier.
  def other_party(person)
    person == starter ? listing.author : starter
  end

  def unit_type
    Maybe(read_attribute(:unit_type)).to_sym.or_else(nil)
  end

end
