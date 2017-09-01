class AddIsApprovedToListings < ActiveRecord::Migration
  def up
    add_column :listings, :is_approved, :boolean, {default: false}
    change_column_default :listings, :open, false
    ActiveRecord::Base.connection.execute('UPDATE listings SET is_approved = 1')
  end
  def down
    remove_column :listings, :is_approved
    change_column_default :listings, :open, true
  end
end
