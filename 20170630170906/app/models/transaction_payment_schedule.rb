class TransactionPaymentSchedule
  include ActiveModel::Model
  attr_accessor :transaction_id, :community_id
  attr_accessor :transaction, :payment, :payment_splits, :booking, :cart, :paid_splits

  def initialize(attributes = {})
    super
    @transaction    ||= Transaction.find(@transaction_id)
    @payment        ||= Payment.find_by_transaction_id(@transaction.id)
    @payment_splits ||= @payment.present? ? @payment.payment_splits : nil
    @paid_splits    ||= @payment.present? ? @payment.payment_splits.where(status: 'paid') : nil
    @booking        ||= @transaction.booking
    @cart           ||= TransactionService::Cart.get_or_create(transaction: @transaction)
  end

  # total price does not include security deposit
  def total_sum
    sum = if @payment.respond_to?(:total_sum)
            # use this first, because once the owner has set a specific sum
            # that becomes the final sum to be payed
            @payment.total_sum
          elsif @cart.total_sum
            # if owner has not yet set final sum, see if a cart has been
            # allready saved and use that to calculate
            @cart.total_sum
          else
            # while a transaction and it's cart still has not been stored in
            # db calculate the sum on the fly
            sum = @transaction.unit_price * @transaction.listing_quantity
            sum += @cart.cart_sum if @cart
            sum
          end
  end

  def total_with_security_deposit_sum
    total_sum + security_deposit_sum
  end

  def first_payment_sum
    total_sum * 0.5
  end

  ## second payment - when and how much
  def second_payment_sum
    total_sum - first_payment_sum
  end

  def second_payment_is_due_on
    if second_payment_is_paid?
      nil
    else
      @booking.start_on - 30.days
    end
  end

  def second_payment_is_due_in(day_count)
    !second_payment_is_paid? && (second_payment_is_due_on <= (Date.current + day_count.days))
  end

  def second_payment_is_paid?
    paid_sum >= total_sum
  end

  def second_payment_is_due?
    second_payment_is_due_in(0)
  end

  ## security deposit - when and how much
  def security_deposit_sum
    @cart.security_deposit
  end

  def security_deposit_is_due_on
    @booking.start_on - 7.days
  end

  def security_deposit_is_due_in(day_count)
    security_deposit_is_due_on <= (Date.current + day_count.days)
  end

  def security_deposit_is_paid?
    paid_sum >= total_with_security_deposit_sum
  end

  def security_deposit_is_due?
    security_deposit_is_due_in(0)
  end

  ## how much do i have to pay
  def paid_sum
    paid = Money.new(0, 'USD')
    paid += @paid_splits.inject(Money.new(0, 'USD')){ |memo, split| memo + split.sum } if @paid_splits.present?
    paid
  end

  def paid_commission
    paid_commission = Money.new(0, 'USD')
    paid_commission += @paid_splits.inject(Money.new(0, 'USD')){ |memo, split| memo + split.commission } if @paid_splits.present?
    paid_commission
  end

  def scheduled_sum
    scheduled = Money.new(0, 'USD')
    scheduled += @payment_splits.inject(Money.new(0, 'USD')){ |memo, split| memo + split.sum } if @payment_splits.present?
    scheduled
  end

  def due_sum_in(day_count)
    to_pay_sum = if second_payment_is_paid? || second_payment_is_due_in(day_count)
      total_sum
    else
      first_payment_sum
    end

    if security_deposit_is_due_in(day_count)
      to_pay_sum += security_deposit_sum
    end

    to_pay_sum - paid_sum
  end

  def due_now_sum
    due_sum_in(0)
  end

  ## Figure out if i can/have to pay
  def next_payment_due_on
    return second_payment_is_due_on unless second_payment_is_paid?
    return security_deposit_is_due_on unless security_deposit_is_paid?
    nil
  end

  def due_payments_paid?
    due_now_sum <= 0
  end

  def all_payments_paid?
    paid_sum >= total_with_security_deposit_sum
  end

  def have_to_pay_now?
    !due_payments_paid?
  end

  def has_paid_nothing_yet?
    paid_sum == 0
  end

  def can_pay_upfront?
    has_paid_nothing_yet? && !security_deposit_is_due?
  end

  def can_pay_second_payment_early?
    !second_payment_is_paid? && !second_payment_is_due?
  end

  def will_have_to_pay_later?
    due_payments_paid? && !all_payments_paid?
  end


  ## Calculate commissions for split payments
  def total_commission
    @payment.total_commission
  end

  def due_commission_in(day_count)
    calculate_commission(due_sum_in(0))
  end

  def due_now_commission
    due_commission_in(0)
  end

  def calculate_commission(amount)
    commission = amount * @payment.total_commission_percentage
    left_to_pay = total_commission - paid_commission #TODO VP with generation of payment schedules, this becomes obsolete
    [commission, left_to_pay].min #TODO VP with generation of payment schedules, this becomes obsolete
  end

  def upfront_payment_schedule_template
    [
      {
        title: :payment,
        amount: total_sum,
        commission: total_commission,
        due_on: second_payment_is_due_on
      },{
        title: :security_deposit,
        amount: security_deposit_sum,
        commission: Money.new(0, 'USD'),
        due_on: security_deposit_is_due_on
      }
    ]
  end

  def standard_payment_schedule_template
    [
      {
        title: :payment_first_split,
        amount: first_payment_sum,
        commission: calculate_commission(first_payment_sum),
        #first payment should be done no later than the second payment
        due_on: second_payment_is_due_on
      },{
        title: :payment_second_split,
        amount: second_payment_sum,
        commission: calculate_commission(second_payment_sum),
        due_on: second_payment_is_due_on
      },{
        title: :security_deposit,
        amount: security_deposit_sum,
        commission: Money.new(0, 'USD'),
        due_on: security_deposit_is_due_on
      }
    ]
  end

  def update_pending_payment_splits(pay_upfront: false)
    if (scheduled_sum < total_with_security_deposit_sum) || # regenerate any payment where the schedule is not complete
      (@payment_splits.count > 3) ||
      (@payment_splits.count == 2 && !pay_upfront) || # regenerate if user does not want to pay upfront, but schedule is prepared for pay_upfront
      (can_pay_upfront? && @payment_splits.count == 3 && pay_upfront) # regenerate if user can and wants to pay_upfront, but schedule is for standard flow

      regenerate_scheduled_splits(pay_upfront)
    end
  end

  def regenerate_scheduled_splits(pay_upfront)
    template_type = pay_upfront ? 'upfront' : 'standard'
    template = self.send(:"#{template_type}_payment_schedule_template")

    amount_paid = paid_sum

    @payment_splits.where(status: 'pending').destroy_all

    #drop template splits for paid amounts
    unpaid_splits   = select_template_splits_for_unpaid_amount(template, amount_paid)

    #merge template splits for due amounts
    mergable_splits = unpaid_splits.select{ |split| split[:due_on] <= Date.today }
    future_splits   = unpaid_splits.select{ |split| split[:due_on] >  Date.today }

    unless mergable_splits.empty?
      merged_split    = mergable_splits.inject({amount: 0, commission: 0, due_on: Date.today}){ |memo, split|
        memo[:amount] += split[:amount] unless split[:amount].nil?
        memo[:commission] += split[:commission] unless split[:commission].nil?
        memo[:due_on] = split[:due_on] if split[:due_on] < memo[:due_on]
        memo
      }

      unpaid_splits = future_splits.unshift(merged_split)
    end

    #create payment_splits from unpaid, merged templates
    unpaid_splits.each do |payment_template|
      PaymentSplit.create({
        payment_id: @payment.id,
        payment: @payment,
        currency: 'USD',
        sum: payment_template[:amount],
        commission: payment_template[:commission],
        due_on: payment_template[:due_on],
        status: 'pending'
      })
    end
  end

  def select_template_splits_for_unpaid_amount(template, amount_paid)
    template.select do |template_split|
      if amount_paid >= template_split[:amount]
        amount_paid -= template_split[:amount]
        false
      else #if amount_paid == 0
        true
      end
    end
  end

  def waiting_refund?
    security_deposit_is_paid? && security_payment_split && !security_payment_split.is_refunded?
  end

  def security_payment_split
    @payment_splits.detect{|ps| ps.sum == security_deposit_sum && ps.commission == 0 && ps.status == 'paid' }
  end

end
