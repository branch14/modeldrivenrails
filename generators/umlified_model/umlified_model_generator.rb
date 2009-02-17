class UmlifiedModelGenerator < Rails::Generator::ModelGenerator

  def associations
    options[:associations]
  end

end
