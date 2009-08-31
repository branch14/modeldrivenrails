require 'zlib'
require 'rexml/document'

require 'logger'

LOG = Logger.new(STDOUT)

# require 'active_support/core_ext/string/inflections'
# String.send(:include, ActiveSupport::CoreExtensions::String::Inflections)

module UML
  
  class Association < Struct.new(:klass, :multiplicities, :name); end
  
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
    
    def associate(oid1, oid2, m1, m2, name)
      k1, k2 = @klasses[oid1], @klasses[oid2]
      name = nil if name.empty?
      LOG.debug("ASSOC #{k1.name} #{m1} -> #{m2} #{k2.name} (#{name})")
      if (m1=='*' or m1=='n') and (m2=='*' or m2=='n')
        if name # named n->n => has_many xxx, :through => yyy
          oid3 = rand.to_s
          k3 = Klass.new(oid3, name)
          self << k3
          k1 << Association.new(k3, "1 -> n")
          k2 << Association.new(k3, "1 -> n")
          k3 << Association.new(k1, "n -> 1")
          k3 << Association.new(k2, "n -> 1")
          k1 << Association.new(k2, "1 -> n", name)
          k2 << Association.new(k1, "1 -> n", name)
        else # unnamed n->n => has_and_belongs_to_many
          k1 << Association.new(k2, "n -> n")
          k2 << Association.new(k1, "n -> n")
        end
      else
        k1 << Association.new(k2, "#{m1} -> #{m2}")
        k2 << Association.new(k1, "#{m2} -> #{m1}")
      end
    end
    
    def emit
      @klasses.each do |oid, klass|
        options = { :associations => [] }
        attributes = klass.attributes.map { |a| "#{a.name}:#{a.type}" }
        klass.associations.each do |assoc|

          case assoc.multiplicities

          when '* -> 1', '* -> 0..1', 'n -> 1', 'n -> 0..1'
            options[:associations] << "belongs_to :#{assoc.klass.name.underscore}"
            attributes << "#{assoc.klass.name.underscore}_id:integer"

          when '1 -> *', '0..1 -> *', '1 -> n', '0..1 -> n'
            params = []
            params << ":#{assoc.klass.name.underscore.pluralize}"
            params << ":through => :#{assoc.name.underscore.pluralize}" if assoc.name
            options[:associations] << "has_many "+params.join(', ')

          when '* -> *', 'n -> n'
            # if the connection is named, a join model
            # will be created under that name, and the relation will be
            # split into '1 -> n' relations

            # if the connection is unnamed, the following is going to happen
            options[:associations] <<  "has_and_belongs_to_many :#{assoc.klass.name.underscore.pluralize}"

            # a migration needs to be generated in this case
            # eg.: script/generate jointable_migration users_roles user_id:integer role_id:integer
            n1 = klass.name.underscore
            n2 = assoc.klass.name.underscore
            jt_args = ['jointable_migration', "#{n1.pluralize}_#{n2.pluralize}"]
            jt_opts = ["#{n1}_id:integer", "#{n2}_id:integer"]
            Rails::Generator::Scripts::Generate.new.run(jt_args, jt_opts)

          end
        end
        args = ['associated_model', klass.name] + attributes
        LOG.debug('-'*60)
        LOG.debug('running generator ...')
        LOG.debug("\targs: #{args.join(' ')}")
        LOG.debug("\toptions: #{options.inspect}")
        LOG.debug('-'*60)
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
        raise "The format '#{ext}' is not supported"
      end
    end

    def self.load_yml(options)
      YAML.load(File.read(options[:filename]))
    end
    
    def self.load_dia(options)

      LOG.debug("loading dia with options: #{options.inspect}")
      # dia is gziped or nongziped xml
      begin # try gzip
        content = Zlib::GzipReader.open(options[:filename]) { |gz| gz.read }
      rescue # fallback to non gzip
        content = File.read(options[:filename])
      end
      root = REXML::Document.new(content).root

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

    def self.load_xmi(options)
      LOG.debug("loading xmi with options: #{options}")
      LOG.debug("Sorry, this implementation is currently in progress.")
      exit
    end
    
    private

    def self.dia_string(xml, name)
      REXML::XPath.first(xml, "child::dia:attribute[@name='#{name}']/dia:string").text.sub(/#(.*)#/, '\1')
    end

  end
  
end
