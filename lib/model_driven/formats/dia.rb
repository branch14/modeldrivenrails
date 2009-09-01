require 'zlib'
require 'rexml/document'
require 'logger'

LOG = Logger.new(STDOUT)

module ModelDriven::Formats::Dia

  def self.load(options)
    
    LOG.debug("loading dia with options: #{options.inspect}")
    
    # dia is gziped or nongziped xml
    begin # try gzip
      content = Zlib::GzipReader.open(options[:filename]) { |gz| gz.read }
    rescue # fallback to non gzip
      content = File.read(options[:filename])
    end

    root = REXML::Document.new(content).root
    
    design = ModelDriven::Design.new

    # go through the classes of all visible layers
    xpath = '/dia:diagram/dia:layer[@visible="true"]/dia:object[@type="UML - Class"]'
    REXML::XPath.each(root, xpath) do |xml_klass|

      oid = xml_klass.attribute(:id).value
      name = dia_string(xml_klass, 'name')
      design << uml_klass = ModelDriven::Klass.new(oid, name)

      # go through the attributes of the class
      xpath = 'child::dia:attribute[@name="attributes"]/dia:composite'
      REXML::XPath.each(xml_klass, xpath) do |attrib|
        name = dia_string(attrib, 'name')
        type = dia_string(attrib, 'type')
        name, type = name.underscore, type.downcase if options[:force_conventions]
        uml_klass << ModelDriven::Attribute.new(name, type)
      end

    end
    
    # go through the associations of all visible layers
    xpath = '/dia:diagram/dia:layer[@visible="true"]/dia:object[@type="UML - Association"]'
    REXML::XPath.each(root, xpath) do |assoc|

      xpath = 'child::dia:attribute[@name="direction"]/dia:enum'
      direction = REXML::XPath.first(assoc, xpath).text.to_i

      # go through multiplicities
      multiplicities = []
      xpath = 'child::dia:attribute[@name="ends"]/dia:composite'
      REXML::XPath.each(assoc, xpath) do |ent|
        multiplicities << dia_string(ent, 'multiplicity')
      end

      # go through connections
      connections = []
      xpath = 'child::dia:connections/dia:connection'
      REXML::XPath.each(assoc, xpath) do |conn|
        to = conn.attribute(:to).value
        handle = conn.attribute(:handle).value.to_i
        connections[handle ^ direction] = to
      end

      name = dia_string(assoc, 'name')
      design.associate(*(connections + multiplicities + [name]))

    end
    
    return design
    
  end
  
  private
  
  def self.dia_string(xml, name)
    xpath = "child::dia:attribute[@name='#{name}']/dia:string"
    REXML::XPath.first(xml, xpath).text.sub(/#(.*)#/, '\1')
  end
  
end
