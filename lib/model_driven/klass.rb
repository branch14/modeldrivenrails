
module ModelDriven
  
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
  
end
