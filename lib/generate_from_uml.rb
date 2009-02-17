
require 'zlib'
require 'rexml/document'

require 'logger'

LOG = Logger.new(STDOUT)

# require 'active_support/core_ext/string/inflections'
# String.send(:include, ActiveSupport::CoreExtensions::String::Inflections)

module UML
  
  class Association < Struct.new(:klass, :multiplicities, :through); end
  
  class Attribute < Struct.new(:name, :type); end
  
  class Klass

    attr_reader :oid, :name

    def initialize(oid, name)
      @oid, @name, @aa = oid, name, []
    end

    def <<(thing)
      @aa << thing
    end
    
    def associations
      @aa.select { |a| a.is_a?(Association) }
    end
    
    def attributes
      @aa.select { |a| a.is_a?(Attribute) }
    end
    
  end
  
  class Design

    attr_reader :klasses # debugging
    
    def initialize
      @klasses = {}
    end
    
    def <<(klass)
      @klasses[klass.oid] = klass
    end
    
    def associate(oid1, oid2, m1, m2)
      @klasses[oid1] << Association.new(@klasses[oid2], "#{m1} -> #{m2}")
      @klasses[oid2] << Association.new(@klasses[oid1], "#{m2} -> #{m1}")
    end
    
    def emit
      @klasses.each do |oid, klass|
        options = { :associations => [] }
        attributes = klass.attributes.map { |a| "#{a.name}:#{a.type}" }
        klass.associations.each do |assoc|
          case assoc.multiplicities
          when '* -> 1', '* -> 0..1'
            options[:associations] << "belongs_to :#{assoc.klass.name.underscore}"
            attributes << "#{assoc.klass.name.underscore}_id:integer"
          when '1 -> *', '0..1 -> *'
            options[:associations] << "has_many :#{assoc.klass.name.underscore.pluralize}"
          #when '* -> *'
          #  options[:associations] << assoc.through ?
          #  "has_many :#{assoc.klass.name.underscore.pluralize}, :through => #{assoc.through.underscore.pluralize}" :
          #    "has_and_belongs_to_many :#{assoc.klass.name.underscore.pluralize}"
          end
        end
        args = ['umlified_model', klass.name] + attributes
        LOG.debug('-'*60+"\nrunning generator ...\n\targs: #{args.join(' ')}\n\toptions: #{options}\n"+'-'*60)
        Rails::Generator::Scripts::Generate.new.run(args, options)
      end
    end
    
    def self.load(options)
      # for now it only supports dia and the internal yaml format
      ext = File.extname(options[:filename])
      case ext
      when '.yml' then load_yml(options)
      when '.dia' then load_dia(options)
      when '.xmi' then load_xmi(options)
      else
        raise "This format '#{ext}' is not supported"
      end
    end

    def self.load_yml(options)
      YAML.load(File.read(options[:filename]))
    end
    
    def self.load_dia(options)
      LOG.debug("loading dia with options: #{options}")
      # dia is gzip'd xml so we'll load it using zlib and rexml
      # TODO fallback to ungzip'd attempt of loading the xml
      root = Zlib::GzipReader.open(options[:filename]) { |gz| REXML::Document.new(gz.read).root }
      design = Design.new
      # go through the classes of all visible layers
      xpath = '/dia:diagram/dia:layer[@visible="true"]/dia:object[@type="UML - Class"]'
      REXML::XPath.each(root, xpath) do |xml_klass|
        oid = xml_klass.attribute(:id).value
        name = dia_string(xml_klass, 'name')
        design << uml_klass = Klass.new(oid, name)
        # go through the attributes of the class
        xpath = 'child::dia:attribute[@name="attributes"]/dia:composite'
        REXML::XPath.each(xml_klass, xpath) do |attrib|
          name = dia_string(attrib, 'name')
          type = dia_string(attrib, 'type')
          name, type = name.underscore, type.downcase if options[:force_conventions]
          uml_klass << Attribute.new(name, type)
        end
      end
      # go through the associations of all visible layers
      xpath = '/dia:diagram/dia:layer[@visible="true"]/dia:object[@type="UML - Association"]'
      REXML::XPath.each(root, xpath) do |assoc|
        direction = REXML::XPath.first(assoc, 'child::dia:attribute[@name="direction"]/dia:enum').text.to_i
        multiplicities = []
        xpath = 'child::dia:attribute[@name="ends"]/dia:composite'
        REXML::XPath.each(assoc, xpath) do |ent|
          multiplicities << dia_string(ent, 'multiplicity')
        end
        connections = []
        xpath = 'child::dia:connections/dia:connection'
        REXML::XPath.each(assoc, xpath) do |conn|
          to = conn.attribute(:to).value
          handle = conn.attribute(:handle).value.to_i
          connections[handle ^ direction] = to
        end
        # design.associate(connections[0], connections[1], multiplicities[0], multiplicities[1])
        design.associate(*(connections + multiplicities))
      end
      return design
    end

    def self.load_xmi(options)
      LOG.debug("loading dia with options: #{options}")
      # dia is gzip'd xml so we'll load it using zlib and rexml
      # TODO fallback to ungzip'd attempt of loading the xml
      root = Zlib::GzipReader.open(options[:filename]) { |gz| REXML::Document.new(gz.read).root }
      design = Design.new
      # go through the classes of all visible layers
      xpath = '/XMI/XMI.content/UML:Model/UML:Namespace.ownedElement/UML:Class'
      REXML::XPath.each(root, xpath) do |xml_klass|
        oid = xml_klass.attribute('xmi.id').value
        name = xml_klass.attribute('name').value
        design << uml_klass = Klass.new(oid, name)
        # go through the attributes of the class
	### AB HIER !!! ###
        xpath = 'child::dia:attribute[@name="attributes"]/dia:composite'
        REXML::XPath.each(xml_klass, xpath) do |attrib|
          name = dia_string(attrib, 'name')
          type = dia_string(attrib, 'type')
          name, type = name.underscore, type.downcase if options[:force_conventions]
          uml_klass << Attribute.new(name, type)
        end
      end
      # go through the associations of all visible layers
      xpath = '/dia:diagram/dia:layer[@visible="true"]/dia:object[@type="UML - Association"]'
      REXML::XPath.each(root, xpath) do |assoc|
        direction = REXML::XPath.first(assoc, 'child::dia:attribute[@name="direction"]/dia:enum').text.to_i
        multiplicities = []
        xpath = 'child::dia:attribute[@name="ends"]/dia:composite'
        REXML::XPath.each(assoc, xpath) do |ent|
          multiplicities << dia_string(ent, 'multiplicity')
        end
        connections = []
        xpath = 'child::dia:connections/dia:connection'
        REXML::XPath.each(assoc, xpath) do |conn|
          to = conn.attribute(:to).value
          handle = conn.attribute(:handle).value.to_i
          connections[handle ^ direction] = to
        end
        # design.associate(connections[0], connections[1], multiplicities[0], multiplicities[1])
        design.associate(*(connections + multiplicities))
      end
      return design
    end
    
    private

    def self.dia_string(xml, name)
      REXML::XPath.first(xml, "child::dia:attribute[@name='#{name}']/dia:string").text.sub(/#(.*)#/, '\1')
    end

  end
  
end
