def dry_setup
  require File.dirname(__FILE__) + '/../../../../config/boot'
  require "#{RAILS_ROOT}/config/environment"
  require 'rails_generator'
  require 'rails_generator/scripts/generate'
  require File.join(File.dirname(__FILE__), "../lib/generate_from_uml")
  options = {
    :filename => ENV['filename'],
    :force_conventions => ENV['force_conventions'] | true # FIXME
  }
end

namespace :uml do
  
  desc "Generate models and associations from uml class diagramm (DIA) or YAML"
  task :generate do
    raise "usage: rake uml:generate filename=<path_to_file>" unless ENV.include?("filename")
    options = dry_setup
    UML::Design.load(options).emit
  end
  
  desc "Convert a Rails app design in a DIA diagram to yaml"
  task :yaml do
    raise "usage: rake uml:yaml filename=<path_to_file>" unless ENV.include?("filename")
    options = dry_setup
    puts UML::Design.load(options).to_yaml
  end

  desc "Purge all in app/models, test/unit, test/fixtures, db/migrate"
  task :purge_ALL do
    begin
      require 'highline'
      highline = HighLine.new
      return unless highline.agree('> Please think twice. Really purge everything?')
      highline.say('> *sigh*')
      ['app/models', 'test/unit', 'test/fixtures', 'db/migrate'].each do |path|
        puts "purging all in #{path}"
        FileUtils.rm Dir.glob("#{path}/*")
      end
      highline.say('> I hope you had a good reason to do that!')
    rescue
      puts "> Sorry, I won't let you use this task if haven't even the highline gem installed."
    end
  end

end
