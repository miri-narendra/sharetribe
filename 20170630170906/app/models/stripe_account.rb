# == Schema Information
#
# Table name: stripe_accounts
#
#  id                     :integer          not null, primary key
#  person_id              :string(255)
#  community_id           :integer
#  access_token           :string(255)
#  refresh_token          :string(255)
#  scope                  :string(255)
#  livemode               :string(255)
#  token_type             :string(255)
#  stripe_user_id         :string(255)
#  stripe_publishable_key :string(255)
#  created_at             :datetime
#  updated_at             :datetime
#  stripe_customer_id     :string(255)
#  stripe_source_info     :string(255)
#
# Indexes
#
#  index_stripe_accounts_on_community_id    (community_id)
#  index_stripe_accounts_on_person_id       (person_id)
#  index_stripe_accounts_on_stripe_user_id  (stripe_user_id)
#

class StripeAccount < ActiveRecord::Base
  belongs_to :person
  belongs_to :community

  validates_presence_of :person
  validates_presence_of :community

  def has_stored_card?
    stripe_customer_id.present? && stripe_source_info.present?
  end
end
