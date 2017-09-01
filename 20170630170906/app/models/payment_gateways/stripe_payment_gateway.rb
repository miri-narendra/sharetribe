# == Schema Information
#
# Table name: payment_gateways
#
#  id                                   :integer          not null, primary key
#  community_id                         :integer
#  type                                 :string(255)
#  braintree_environment                :string(255)
#  braintree_merchant_id                :string(255)
#  braintree_master_merchant_id         :string(255)
#  braintree_public_key                 :string(255)
#  braintree_private_key                :string(255)
#  braintree_client_side_encryption_key :text(65535)
#  checkout_environment                 :string(255)
#  checkout_user_id                     :string(255)
#  checkout_password                    :string(255)
#  created_at                           :datetime         not null
#  updated_at                           :datetime         not null
#  stripe_api_key                       :string(255)
#  stripe_client_id                     :string(255)
#  stripe_publishable_key               :string(255)
#  stripe_livemode                      :boolean
#

class StripePaymentGateway < PaymentGateway
  def can_receive_payments?(person)
    stripe_account = person.stripe_account
    stripe_account.present?
  end

  def new_payment_path(person, message, locale, options={})
    if options[:pay_upfront]
      edit_person_message_stripe_payment_path(
        id: message.payment.id,
        person_id: person.id.to_s,
        message_id: message.id.to_s,
        locale: locale,
        pay_upfront: true
      )
    else
      edit_person_message_stripe_payment_path(
        id: message.payment.id,
        person_id: person.id.to_s,
        message_id: message.id.to_s,
        locale: locale
      )
    end
  end

  def new_payment_url(person, message, locale, other_params={})
    edit_person_message_stripe_payment_url(other_params.merge(
      id: message.payment.id,
      person_id: person.id.to_s,
      message_id: message.id.to_s,
      locale: locale
    ))
  end

  def has_additional_terms_of_use
    true #TODO where is this needed?
  end

  def name
    'stripe'
  end

  def form_template_dir
    'payments/simple_form'
  end

  def invoice_form_type
    'simple'
  end

  def new_payment
    payment = StripePayment.new
    payment.payment_gateway = self
    payment.community = community
    payment.currency = 'USD'
    payment
  end

  def hold_in_escrow
    false #TODO escrow should be elimitated from this
  end

  def configured?
    true
    #[
    #  braintree_environment,
    #  braintree_merchant_id,
    #  braintree_master_merchant_id,
    #  braintree_public_key,
    #  braintree_private_key,
    #  braintree_client_side_encryption_key
    #].all? { |x| x.present? }
  end

  def gateway_type
    :stripe
  end
end
