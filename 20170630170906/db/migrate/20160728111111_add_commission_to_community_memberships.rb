class AddCommissionToCommunityMemberships < ActiveRecord::Migration
  def up
    add_column :community_memberships, :commission_percent, :integer
    Person.connection.execute("UPDATE community_memberships SET commission_percent = 20")
  end
  def down
    remove_column :community_memberships, :commission_percent
  end
end
