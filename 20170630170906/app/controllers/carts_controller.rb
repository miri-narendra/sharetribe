class CartsController < ApplicationController
  def update
    cart = Cart.find(params[:id])
    transaction = cart.tx
    if transaction.current_state == "pending" && transaction.seller == @current_user
      converted_params = convert_nested_amount_to_cents(params)
      cart_prms = cart_params(converted_params, cart.allow_pickup_dropoff_fee?)
      cart.update_attributes(cart_prms)
    end
    redirect_to person_transaction_path(person_id: @current_user.id, id: transaction.id)
  end

  private

  def convert_nested_amount_to_cents(all_params)
    all_params[:cart][:other_fees_attributes].each do |other_fee|
      amount = all_params[:cart][:other_fees_attributes][other_fee[0]].delete(:amount)
      all_params[:cart][:other_fees_attributes][other_fee[0]][:amount_cents] = Monetize.parse(amount).cents
    end if all_params[:cart][:other_fees_attributes]
    all_params
  end

  def cart_params(all_params, allow_pickup_dropoff_fee)
    fields = [
      :discount,
      other_fees_attributes: [:amount_cents, :id, :name, :_destroy]
    ]
    fields = fields.unshift(:pickup_dropoff_fee)
    all_params.require(:cart).permit(fields)
  end
end
