module TransactionService::PaymentSchedule

  module_function

  def new(community_id:, listing_price:, booking_start_on:, booking_end_on:, duration:, cart: nil)
    transaction = ::Transaction.new
    transaction.unit_price = listing_price
    transaction.listing_quantity = duration
    booking = Booking.new
    booking.start_on = booking_start_on
    booking.end_on = booking_end_on
    payment = Payment.new
    payment_splits = []
    TransactionPaymentSchedule.new(community_id: community_id, transaction_id: nil,
                                   transaction: transaction, payment: payment,
                                   payment_splits: payment_splits, booking: booking, cart: cart)
  end

  def get(community_id:, transaction_id:)
    TransactionPaymentSchedule.new(community_id: community_id, transaction_id: transaction_id)

    # 50% first payment
    # 50% 30 days before rental
    # security deposit 7 days before rental

    # status = payment_due, partialy_paid, paid

    # amounts:
    #  authorized
    #  paid
    #  due_now
    #  payable_later
    #
    #  rental
    #  security deposit

    # current time vs schedule

  end
end
