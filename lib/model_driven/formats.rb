
Dir.glob('formats/*.rb') do |f|
  require(File.join(Dir.pathname(__FILE__), *%w(formats #{f})))
end

module ModelDriven::Formats

end
