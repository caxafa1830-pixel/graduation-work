class CreateCatchRecords < ActiveRecord::Migration[7.2]
  def change
    create_table :catch_records do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :fish_size_cm
      t.integer :score

      t.timestamps
    end
  end
end
