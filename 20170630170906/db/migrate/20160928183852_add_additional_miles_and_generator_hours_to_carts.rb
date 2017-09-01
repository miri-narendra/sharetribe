class AddAdditionalMilesAndGeneratorHoursToCarts < ActiveRecord::Migration
  def change
    add_column :carts, :additional_miles, :integer
    add_column :carts, :generator_hours, :integer
  end
end
