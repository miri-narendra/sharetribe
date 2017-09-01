class AddAllowInquiryToCommunityMemberships < ActiveRecord::Migration
  def up
    add_column :community_memberships, :allow_inquiry, :boolean, default: 0
    ActiveRecord::Base.connection.execute('UPDATE community_memberships SET allow_inquiry = 0')
  end

  def down
    remove_column :community_memberships, :allow_inquiry
  end
end
