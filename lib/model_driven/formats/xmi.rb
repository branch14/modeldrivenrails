#require 'zlib'
#require 'rexml/document'
require 'logger'

LOG = Logger.new(STDOUT)

module ModelDriven::Formats::Xmi

  def self.load(options)

    LOG.debug("loading xmi with options: #{options}")
    LOG.debug("Sorry, this implementation is currently in progress.")
    exit

  end
  
end
