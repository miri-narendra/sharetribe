class MoveIsOwnerToCommunityMemberships < ActiveRecord::Migration
  def up
    add_column :community_memberships, :is_owner, :boolean, default: 0
    ActiveRecord::Base.connection.execute('UPDATE community_memberships SET is_owner = 0')
    ActiveRecord::Base.connection.execute('UPDATE community_memberships SET is_owner = 1 WHERE person_id IN (SELECT id FROM people WHERE is_owner = 1)')
    remove_column :people, :is_owner
  end

  def down
    add_column :people, :is_owner, :boolean
    ActiveRecord::Base.connection.execute('UPDATE people SET is_owner = 0')
    ActiveRecord::Base.connection.execute('UPDATE people SET is_owner = 1 WHERE id IN (SELECT person_id FROM community_memberships WHERE is_owner = 1)')
    remove_column :community_memberships, :is_owner
  end
end
