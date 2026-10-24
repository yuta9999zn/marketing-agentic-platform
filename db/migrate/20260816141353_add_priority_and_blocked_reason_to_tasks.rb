class AddPriorityAndBlockedReasonToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :priority, :string
    add_column :tasks, :blocked_reason, :text
    add_index  :tasks, :priority
    reversible do |dir|
      dir.up { execute "UPDATE tasks SET priority = 'medium' WHERE priority IS NULL" }
    end
  end
end
