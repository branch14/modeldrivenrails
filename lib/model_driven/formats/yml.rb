
module ModelDriven::Formats::Yml

  def self.load(options)

    YAML.load(File.read(options[:filename]))

  end
  
end
