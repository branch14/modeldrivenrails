class <%= class_name %> < ActiveRecord::Base

  <%= associations.join("\n  ") %>

end
