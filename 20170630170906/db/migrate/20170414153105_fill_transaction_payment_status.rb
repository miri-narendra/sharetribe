class FillTransactionPaymentStatus < ActiveRecord::Migration
  def self.up
    Transaction.all.each do |transaction|
      community = transaction.community
      payment = transaction.payment
      if !payment
        transaction.payment_status = Transaction::NOT_PAID
        transaction.save
        next
      end

      if payment.status == 'partial'
        transaction.payment_status = Transaction::PARTIALLY_PAID
      elsif payment.status == 'paid'
        transaction.payment_status = if payment.payment_splits.pending.count > 0 then
          Transaction::PAID
        else
          Transaction::PAID_INCLUDING_DEPOSIT
        end
      else
        transaction.payment_status = Transaction::NOT_PAID
      end
      transaction.save
    end
  end

  def self.down
  end
end
