class InboxesController < ApplicationController
  include MoneyRails::ActionViewExtension

  before_filter do |controller|
    controller.ensure_logged_in t("layouts.notifications.you_must_log_in_to_view_your_inbox")
  end

  def show
    # We use pageless scroll, so the page should be always the first one (1) when request was not AJAX request
    params[:page] = 1 unless request.xhr?

    pagination_opts = PaginationViewUtils.parse_pagination_opts(params)

    inbox_rows = MarketplaceService::Inbox::Query.inbox_data(
      @current_user.id,
      @current_community.id,
      pagination_opts[:limit],
      pagination_opts[:offset])

    count = MarketplaceService::Inbox::Query.inbox_data_count(@current_user.id, @current_community.id)

    inbox_rows = inbox_rows.map { |inbox_row|
      extended_inbox = inbox_row.merge(
        path: path_to_conversation_or_transaction(inbox_row),
        other: person_entity_with_url(inbox_row[:other]),
        last_activity_ago: time_ago(inbox_row[:last_activity_at]),
        title: inbox_title(inbox_row, inbox_payment(inbox_row))
      )

      if inbox_row[:type] == :transaction
        extended_inbox.merge(
          listing_url: listing_path(id: inbox_row[:listing_id])
        )
      else
        extended_inbox
      end
    }

    paginated_inbox_rows = WillPaginate::Collection.create(pagination_opts[:page], pagination_opts[:per_page], count) do |pager|
      pager.replace(inbox_rows)
    end

    if request.xhr?
      render :partial => "inbox_row",
        :collection => paginated_inbox_rows, :as => :conversation,
        locals: {
          payments_in_use: @current_community.payments_in_use?
        }
    else
      render locals: {
        inbox_rows: paginated_inbox_rows,
        payments_in_use: @current_community.payments_in_use?,
        dashboard: renter_dashboard_hash
      }
    end
  end

  private

  def inbox_title(inbox_item, payment_sum)
    title = if MarketplaceService::Inbox::Entity.last_activity_type(inbox_item) == :message
      inbox_item[:last_message_content]
    else
      action_messages = TransactionViewUtils.create_messages_from_actions(
        inbox_item[:transitions],
        inbox_item[:other],
        inbox_item[:starter],
        payment_sum
      )

      action_messages.last[:content] if action_messages.last
    end
  end

  def inbox_payment(inbox_item)
    Maybe(inbox_item)[:payment_total].or_else(nil)
  end

  def path_to_conversation_or_transaction(inbox_item)
    if inbox_item[:type] == :transaction
      person_transaction_path(:person_id => inbox_item[:current][:username], :id => inbox_item[:transaction_id])
    else
      single_conversation_path(:conversation_type => "received", :id => inbox_item[:conversation_id])
    end
  end

  def person_entity_with_url(person_entity)
    person_entity.merge({
                          url: person_path(username: person_entity[:username]),
                          display_name: PersonViewUtils.person_entity_display_name(person_entity, @current_community.name_display_type)
                        })
  end

  def renter_dashboard_hash
    dashboard = {
      show_renter_dashboard: !@current_user.is_owner?,
    }
    if dashboard[:show_renter_dashboard]

      transactions_with_payment = Transaction.where(starter_id: @current_user)
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

      dashboard.merge!({
        booked_trips: booked_trips,
        days_till_next_trip: days_till_next_trip,
        payments_made: paid_split_sum,
        next_payment_due: next_payment_due_sum
      })
    end
    dashboard
  end
end
