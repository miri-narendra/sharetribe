class AddIncludedMilesAnsGeneratorHoursToCarts < ActiveRecord::Migration
  def change
    add_column :carts, :included_miles_per_day, :integer
    add_column :carts, :included_generator_hours_per_day, :integer
    rename_column :carts, :generator_hours, :additional_generator_hours
  end
end
