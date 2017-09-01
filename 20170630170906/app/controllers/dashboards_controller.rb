class DashboardsController < ApplicationController
  include MoneyRails::ActionViewExtension

  before_filter do |controller|
    controller.ensure_logged_in t("layouts.notifications.you_must_log_in_to_view_your_dashboard")
  end

  before_filter do |controller|
    controller.ensure_is_owner t("layouts.notifications.you_must_be_owner_to_view_your_dashboard")
  end

  def show
    # We use pageless scroll, so the page should be always the first one (1) when request was not AJAX request
    params[:page] = 1 unless request.xhr?

    pagination_opts = PaginationViewUtils.parse_pagination_opts(params)

    transaction_rows = Transaction.where(community_id: @current_community.id)
                                  .where("(starter_id = ? OR listing_author_id = ?)", @current_user.id, @current_user.id)
                                  .joins(:payment)
                                  .includes(:listing)
                                  .includes(:booking)
                                  .includes(:cart)
                                  .includes(payment: [:payment_splits])
                                  .order("bookings.start_on DESC")
                                  .paginate(page: params[:page])

    if request.xhr?
      render :partial => "transaction_row",
        :collection => transaction_rows, :as => :transaction,
        locals: {
          payments_in_use: @current_community.payments_in_use?
        }
    else
      render locals: {
        transaction_rows: transaction_rows,
        payments_in_use: @current_community.payments_in_use?,
        dashboard: owner_dashboard_hash
      }
    end
  end

  private

  def owner_dashboard_hash
    transactions_with_payment = Transaction.where(listing_author_id: @current_user)
                                           .where(current_state: [:accepted, :paid, :confirmed])
                                           .joins(payment: [:payment_splits])
                                           .where("payment_splits.status = 'paid'")
                                           .distinct

    # booked_trips
    booked_trips = transactions_with_payment.count

    # days_till_next_trip
    next_booking = transactions_with_payment.joins(:booking).where("bookings.start_on >= CURRENT_DATE").order('bookings.start_on ASC').limit(1).first
    days_till_next_trip = if next_booking.present?
                            days = (next_booking.booking.start_on - Date.today).to_i
                            (days >= 0 ? days : '-')
                          else
                            '-'
                          end

    # payments_made & next_payment_due
    payment_ids = Payment.where(transaction_id: transactions_with_payment.map(&:id)).map(&:id)
    paid_split_sum_by_currency = PaymentSplit.where(payment_id: payment_ids, status: :paid).group(:currency).sum(:sum_cents)
    # system uses only USD
    paid_split_sum    = if paid_split_sum_by_currency.present?
                          Money.new(paid_split_sum_by_currency.first[1], paid_split_sum_by_currency.first[0])
                        else
                          Money.new(0, "USD")
                        end

    next_payment_due = PaymentSplit.where(payment_id: payment_ids, status: :pending).order('due_on ASC').first
    next_payment_due_sum = next_payment_due.present? ? next_payment_due.sum : '-'

    dashboard = {
      booked_trips: booked_trips,
      days_till_next_trip: days_till_next_trip,
      payments_received: paid_split_sum,
      next_payment_due: next_payment_due_sum
    }
  end
end
