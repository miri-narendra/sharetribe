class AddCommissionPercentToPayments < ActiveRecord::Migration
  def up
    add_column :payments, :commission_percent, :integer
    ActiveRecord::Base.connection.execute('UPDATE payments SET commission_percent = 20')
  end

  def down
    add_column :payments, :commission_percent
  end
end
