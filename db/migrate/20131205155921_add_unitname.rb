class AddUnitname < ActiveRecord::Migration
  def up
    create_table :dojos, force: true do |t|
      t.string   "userid"
      t.string   "username"
      t.string   "unitname"
      t.integer  "level"
      t.integer  "dispvalue"
      t.string   "comment"
      t.datetime "created_at"
      t.datetime "updated_at"
    end
  end

  def down
    drop_table :dojos
  end
end
