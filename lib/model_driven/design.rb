require 'logger'

LOG = Logger.new(STDOUT)

module ModelDriven

  class Design

    # attr_reader :klasses # for debugging

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

        if name # named n-n ==> has_many :through

          if matches = @klasses.select { |d, k| k.name==name }
            # if a model with same name exists
            # it needs to be the jointable model
            k3 = matches.first
          else
            # if no model with same name exists
            # it will be generated
            oid3 = rand.to_s
            k3 = Klass.new(oid3, name)
            self << k3
            k1 << Association.new(k3, "1 -> n")
            k2 << Association.new(k3, "1 -> n")
            k3 << Association.new(k1, "n -> 1")
            k3 << Association.new(k2, "n -> 1")
          end

          # has_many :through
          k1 << Association.new(k2, "1 -> n", name)
          k2 << Association.new(k1, "1 -> n", name)

        else # unnamed n-n ==> has_and_belongs_to_many

          k1 << Association.new(k2, "n -> n")
          k2 << Association.new(k1, "n -> n")

        end

      else

        k1 << Association.new(k2, "#{m1} -> #{m2}")
        k2 << Association.new(k1, "#{m2} -> #{m1}")

      end

    end

    def emit

      # go through all klasses
      @klasses.each do |oid, klass|
        options = { :associations => [] }
        attributes = klass.attributes.map { |a| "#{a.name}:#{a.type}" }

        # go through all associations of current klass
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
            options[:associations] << "has_and_belongs_to_many :" +
              assoc.klass.name.underscore.pluralize

            # a migration needs to be generated in this case
            # eg.: script/generate jointable_migration user_roles\
            #                      user_id:integer role_id:integer
            n1 = klass.name.underscore
            n2 = assoc.klass.name.underscore
            jt1 = "#{n1.pluralize}_#{n2.pluralize}"
            jt2 = "#{n2.pluralize}_#{n1.pluralize}"
            unless (migration_exists?("create_"+jt1) or
                    migration_exists?("create_"+jt2))
              args = ['jointable_migration', jt1,
                      "#{n1}_id:integer", "#{n2}_id:integer"]
              LOG.debug('running generator for jointable migration ...')
              LOG.debug("\targs: #{args.join(' ')}")
              Rails::Generator::Scripts::Generate.new.run(args)
              # hack! to solve the timestamp issue with migrations
              sleep 1
            end

          end
        end
        args = ['associated_model', klass.name] + attributes
        LOG.debug('running generator for associated model ...')
        LOG.debug("\targs: #{args.join(' ')}")
        LOG.debug("\toptions: #{options.inspect}")
        # hack! to solve dependency problem on has_many :through
        # but also eye candy, since assocs will be ordered nicely
        options[:associations].sort! { |a, b| a.size <=> b.size }
        unless  migration_exists?("create_" + klass.name.underscore.pluralize)
          Rails::Generator::Scripts::Generate.new.run(args, options)
          # hack! to solve the timestamp issue with migrations
          sleep 1
        else
          LOG.debug('WARNING: Migration already exists. Skipping ...')
        end
      end
    end

    def self.load(options)
      ext = File.extname(options[:filename])
      case ext
      when '.yml' then Formats::Yml::load(options)
      when '.dia' then Formats::Dia::load(options)
        #when '.xmi' then Formats::Xmi::load(options)
      else
        raise "The format '#{ext}' is not supported"
      end
    end

    def existing_migrations(file_name)
      migration_directory = "#{RAILS_ROOT}/db/migrate"
      pattern = "#{migration_directory}/[0-9]*_*.rb"
      Dir.glob(pattern).grep(/[0-9]+_#{file_name}.rb$/)
    end

    def migration_exists?(file_name)
      not existing_migrations(file_name).empty?
    end

  end

end
