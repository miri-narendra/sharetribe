module TransactionService::Process
  class Free

    def create(tx:, gateway_fields:, gateway_adapter:, prefer_async:)
      Transition.transition_to(tx[:id], :free)
      Result::Success.new({result: true})
    end

  end
end
