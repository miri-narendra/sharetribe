class AddIsOwnerToPeople < ActiveRecord::Migration
  def up
    add_column :people, :is_owner, :boolean
    ActiveRecord::Base.connection.execute('UPDATE people SET is_owner = 1')
  end

  def down
    remove_column :people, :is_owner
  end
end
