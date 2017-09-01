module TransactionViewUtils
  extend MoneyRails::ActionViewExtension
  extend ActionView::Helpers::TranslationHelper
  extend ActionView::Helpers::TagHelper

  MessageBubble = EntityUtils.define_builder(
    [:content, :string, :mandatory],
    [:sender, :hash, :mandatory],
    [:created_at, :time, :mandatory],
    [:mood, one_of: [:positive, :negative, :neutral]]
  )

  PriceBreakDownLocals = EntityUtils.define_builder(
    [:transaction_status, :string],
    [:listing_price, :money, :mandatory],
    [:localized_unit_type, :string],
    [:localized_selector_label, :string],
    [:booking, :to_bool, default: false],
    [:start_on, :date],
    [:end_on, :date],
    [:duration, :fixnum],
    [:quantity, :fixnum],
    [:cart, :hash],
    [:subtotal, :money],
    [:security_deposit, :money],
    [:paid_sum, :money],
    [:due_now_sum, :money],
    [:second_payment_is_due_on, :date],
    [:second_payment_sum, :money],
    [:total, :money],
    [:security_deposit_is_due_on, :date],
    [:security_deposit_sum, :money],
    [:shipping_price, :money],
    [:total_label, :string])



  module_function

  def merge_messages_and_transitions(messages, transitions, payment_messages = [])
    messages = messages.map { |msg| MessageBubble[msg] }
    transitions = transitions.map { |tnx| MessageBubble[tnx] }
    payment_messages = payment_messages.map { |tnx| MessageBubble[tnx] }

    (messages + transitions + payment_messages).sort_by { |hash| hash[:created_at] }
  end

  def create_messages_from_actions(transitions, author, starter, payment_sum)
    return [] if transitions.blank?

    ignored_transitions = ["free", "pending", "initiated", "pending_ext", "errored", "paid"] # Transitions that should not generate auto-message

    previous_states = [nil] + transitions.map { |transition| transition[:to_state] }

    transitions
      .zip(previous_states)
      .reject { |(transition, previous_state)|
        ignored_transitions.include? transition[:to_state]
      }
      .map { |(transition, previous_state)|
        create_message_from_action(transition, previous_state, author, starter, payment_sum)
      }
  end

  def conversation_messages(message_entities, name_display_type)
    message_entities.map { |message_entity|
      sender = message_entity[:sender].merge(
        display_name: PersonViewUtils.person_entity_display_name(message_entity[:sender], name_display_type))
      message_entity.merge(mood: :neutral, sender: sender)
    }
  end

  def transition_messages(transaction, conversation, name_display_type)
    if transaction.present?
      author = conversation[:other_person].merge(
        display_name: PersonViewUtils.person_entity_display_name(conversation[:other_person], name_display_type))
      starter = conversation[:starter_person].merge(
        display_name: PersonViewUtils.person_entity_display_name(conversation[:starter_person], name_display_type))

      transitions = transaction[:transitions]
      payment_sum = transaction[:payment_total]

      create_messages_from_actions(transitions, author, starter, payment_sum)
    else
      []
    end
  end

  def payment_split_messages(transaction, conversation, payment, name_display_type)
    if transaction.present? && payment.present? && payment.payment_splits.present?
      author = conversation[:other_person].merge(
        display_name: PersonViewUtils.person_entity_display_name(conversation[:other_person], name_display_type))
      starter = conversation[:starter_person].merge(
        display_name: PersonViewUtils.person_entity_display_name(conversation[:starter_person], name_display_type))

      payment.payment_splits.select do |payment_split|
        payment_split.status == 'paid'
      end.map do |payment_split| 
        create_message_from_action({to_state: 'paid', from_state: 'paid', created_at: payment_split.updated_at}, 'paid', author, starter, payment_split.sum)
      end
    else
      []
    end
  end

  def create_message_from_action(transition, old_state, author, starter, payment_sum)
    preauthorize_accepted = ->(new_state) { new_state == "paid" && old_state == "preauthorized" }
    post_pay_accepted = ->(new_state) {
      # The condition here is simply "if new_state is paid", since due to migrations from old system there might be
      # transitions in "paid" state without previous state.
      new_state == "paid"
    }

    message = case transition[:to_state]
    when "preauthorized"
      {
        sender: starter,
        mood: :positive
      }
    when "accepted"
      {
        sender: author,
        mood: :positive
      }
    when "rejected"
      {
        sender: author,
        mood: :negative
      }
    when preauthorize_accepted
      {
        sender: author,
        mood: :positive
      }
    when post_pay_accepted
      {
        sender: starter,
        mood: :positive
      }
    when "canceled"
      sender_id = transition[:metadata] && transition[:metadata]["sender"] 
      {
        sender: author[:id] == sender_id ? author : starter,
        mood: :negative
      }
    when "confirmed"
      {
        sender: starter,
        mood: :positive
      }
    else
      raise("Unknown transition to state: #{transition[:to_state]}")
    end

    MessageBubble[message.merge(
      created_at: transition[:created_at],
      content: create_content_from_action(transition[:to_state], old_state, payment_sum, transition[:metadata])
    )]
  end

  def create_content_from_action(state, old_state, payment_sum, metadata = nil)
    preauthorize_accepted = ->(new_state) { new_state == "paid" && old_state == "preauthorized" }
    post_pay_accepted = ->(new_state) {
      # The condition here is simply "if new_state is paid", since due to migrations from old system there might be
      # transitions in "paid" state without previous state.
      new_state == "paid"
    }

    message = case state
    when "preauthorized"
      t("conversations.message.payment_preauthorized", sum: humanized_money_with_symbol(payment_sum))
    when "accepted"
      if metadata.present? && (metadata["action"] || metadata[:action]) == "create_offer"
        t("conversations.message.offer_created")
      else
        t("conversations.message.accepted_request")
      end
    when "rejected"
      t("conversations.message.rejected_request")
    when preauthorize_accepted
      t("conversations.message.received_payment", sum: humanized_money_with_symbol(payment_sum))
    when post_pay_accepted
      t("conversations.message.paid", sum: humanized_money_with_symbol(payment_sum))
    when "canceled"
      t("conversations.message.canceled_request")
    when "confirmed"
      t("conversations.message.confirmed_request")
    else
      raise("Unknown transition to state: #{state}")
    end
  end

  def price_break_down_locals(opts)
    PriceBreakDownLocals.call(opts)
  end

  def parse_booking_date(str)
    Date.parse(str) unless str.blank?
  end

  def stringify_booking_date(date)
    date.iso8601
  end

  def parse_quantity(quantity)
    Maybe(quantity)
      .select { |q| StringUtils.is_numeric?(q) }
      .map(&:to_i)
      .select { |q| q > 0 }
      .or_else(1)
  end


end
