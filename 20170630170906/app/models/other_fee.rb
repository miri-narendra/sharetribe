# == Schema Information
#
# Table name: other_fees
#
#  id           :integer          not null, primary key
#  cart_id      :integer
#  name         :string(255)
#  amount_cents :integer
#  currency     :string(255)
#
# Indexes
#
#  index_other_fees_on_cart_id  (cart_id)
#

class OtherFee < ActiveRecord::Base
  belongs_to :cart
  monetize :amount_cents

  validates :name, presence: true
  validates :amount, presence: true
end
