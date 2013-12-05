class CreateDojos < ActiveRecord::Migration
  def up
    create_table :dojos do |t|
      t.string  :userid
      t.string  :name
      t.integer :level
      t.integer :dispvalue
      t.string  :comment
      t.timestamps
    end
  end

  def down
    drop_table :dojos
  end
end
