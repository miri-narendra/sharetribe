class TransactionProcessStateMachine
  include Statesman::Machine

  state :not_started, initial: true
  state :free
  state :initiated
  state :pending
  state :preauthorized
  state :pending_ext
  state :accepted
  state :rejected
  state :errored
  state :paid
  state :confirmed
  state :canceled

  transition from: :not_started,               to: [:free, :pending, :preauthorized, :initiated]
  transition from: :initiated,                 to: [:preauthorized]
  transition from: :pending,                   to: [:accepted, :rejected]
  transition from: :preauthorized,             to: [:paid, :rejected, :pending_ext, :errored]
  transition from: :pending_ext,               to: [:paid, :rejected]
  transition from: :accepted,                  to: [:paid, :canceled]
  transition from: :paid,                      to: [:confirmed, :canceled]


  guard_transition(to: :pending) do |conversation|
    conversation.requires_payment?(conversation.community)
  end

  after_transition(to: :accepted) do |transaction, transition|
    if transaction.is_offer
      current_community = transaction.community
      Delayed::Job.enqueue(OfferCreatedJob.new(transaction.id, current_community.id))
      #payment reminders are created when the first payment is done
      #see app/controllers/stripe_payments_controller.rb
    else
      accepter = transaction.listing.author
      current_community = transaction.community

      Delayed::Job.enqueue(TransactionStatusChangedJob.new(transaction.id, accepter.id, current_community.id))

      TransactionService::Transaction.schedule_payment_reminders(current_community, transaction, skip_first_reminder: false)
    end
  end

  after_transition(to: :paid) do |transaction|
    payer = transaction.starter
    current_community = transaction.community

    if transaction.booking.present?
      automatic_booking_confirmation_at = transaction.booking.end_on + 2.day
      ConfirmConversation.new(transaction, payer, current_community).activate_automatic_booking_confirmation_at!(automatic_booking_confirmation_at)
    else
      ConfirmConversation.new(transaction, payer, current_community).activate_automatic_confirmation!
    end

    Delayed::Job.enqueue(SendPaymentReceipts.new(transaction.id))
  end

  after_transition(to: :rejected) do |transaction|
    rejecter = transaction.listing.author
    current_community = transaction.community

    Delayed::Job.enqueue(TransactionStatusChangedJob.new(transaction.id, rejecter.id, current_community.id))
  end

  after_transition(to: :confirmed) do |conversation|
    confirmation = ConfirmConversation.new(conversation, conversation.starter, conversation.community)
    confirmation.confirm!
  end

  after_transition(from: :accepted, to: :canceled) do |conversation|
    confirmation = ConfirmConversation.new(conversation, conversation.starter, conversation.community)
    confirmation.cancel!
  end

  after_transition(from: :paid, to: :canceled) do |conversation|
    confirmation = ConfirmConversation.new(conversation, conversation.starter, conversation.community)
    confirmation.cancel!
    confirmation.cancel_escrow!
  end

end
