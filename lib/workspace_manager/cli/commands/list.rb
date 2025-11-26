# frozen_string_literal: true

require 'json'
require 'optparse'

module WorkspaceManager
  module CLI
    module Commands
      module List
        module_function

        def call(context, args)
          options = parse_options(context, args)

          history_entries = History.read(context)

          if history_entries.empty?
            Output.log(context, :info, 'No workspace sessions found.')
            return
          end

          sorted = history_entries.sort_by { |entry| entry['timestamp'].to_s }
          sorted.reverse! unless options[:reverse]

          sessions = sorted.map do |entry|
            manifest = History.manifest_for(context, entry['session_id'])
            History.session_snapshot(context, entry, manifest)
          end

          sessions.select! { |session| session['status'] == 'active' } if options[:active_only]
          sessions = sessions.first(options[:limit]) if options[:limit]

          if sessions.empty?
            Output.log(context, :info, 'No workspace sessions matched the filters.')
            return
          end

          if options[:json]
            context[:stdout].puts JSON.pretty_generate(sessions)
            return
          end

          SessionRenderer.render(context, sessions)
        end

        def parse_options(context, args)
          options = {
            limit: nil,
            active_only: false,
            json: false,
            reverse: false
          }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: #{context[:command_name]} list [options]"
            opts.on('--limit N', Integer, 'Limit the number of sessions displayed') { |value| options[:limit] = value }
            opts.on('--active', 'Show only sessions with existing worktrees') { options[:active_only] = true }
            opts.on('--json', 'Output JSON instead of text') { options[:json] = true }
            opts.on('--reverse', 'Show oldest sessions first') { options[:reverse] = true }
            opts.on('-h', '--help', 'Show this help') do
              context[:stdout].puts opts
              exit
            end
          end

          parser.parse!(args)
          options
        end
      end
    end
  end
end
