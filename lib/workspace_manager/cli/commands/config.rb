# frozen_string_literal: true

require 'json'
require 'optparse'

module WorkspaceManager
  module CLI
    module Commands
      module Config
        module_function

        def call(context, args)
          parse_options(context, args)

          config = context[:config]
          data = config.to_h

          context[:stdout].puts(JSON.pretty_generate(data))
        end

        def parse_options(context, args)
          parser = OptionParser.new do |opts|
            opts.banner = "Usage: #{context[:command_name]} config"
            opts.on('-h', '--help', 'Show this help') do
              context[:stdout].puts(opts)
              exit
            end
          end

          parser.parse!(args)
        end
      end
    end
  end
end
