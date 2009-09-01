
Dir.glob('model_driven/*.rb') do |f|
  require(File.join(Dir.pathname(__FILE__), *%w(model_driven #{f})))
end

module ModelDriven

  VERSION = '0.2.0'

end
