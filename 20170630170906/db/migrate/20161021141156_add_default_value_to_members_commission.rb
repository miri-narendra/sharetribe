class AddDefaultValueToMembersCommission < ActiveRecord::Migration
  def up
    change_column_default :community_memberships, :commission_percent, 100
  end
  def down
    change_column_default :community_memberships, :commission_percent, nil
  end
end
