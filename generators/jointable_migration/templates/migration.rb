class <%= migration_name %> < ActiveRecord::Migration
  def self.up
    create_table :<%= table_name %>, :id => false do |t|
<% for attribute in attributes -%>
      t.<%= attribute.type %> :<%= attribute.name %>
<% end -%>
    end
  end

  def self.down
    drop_table :<%= table_name %>
  end
end
