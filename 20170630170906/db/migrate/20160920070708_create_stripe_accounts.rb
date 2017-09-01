class CreateStripeAccounts < ActiveRecord::Migration
  def change
    create_table :stripe_accounts do |t|
      t.string :person_id
      t.integer :community_id
      
      t.string :access_token
      t.string :refresh_token
      t.string :scope
      t.string :livemode
      t.string :token_type
      t.string :stripe_user_id
      t.string :stripe_publishable_key

      t.timestamps
    end
    add_index :stripe_accounts, :person_id
    add_index :stripe_accounts, :community_id
    add_index :stripe_accounts, :stripe_user_id
  end
end
