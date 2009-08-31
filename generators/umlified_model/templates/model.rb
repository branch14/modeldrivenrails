class <%= class_name %> < ActiveRecord::Base

  <%= associations.join("\n\t") %>

end
