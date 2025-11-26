# frozen_string_literal: true

require 'optparse'

module WorkspaceManager
  module CLI
    module Commands
      module Open
        module_function

        def call(context, args)
          options = parse_options(context, args)

          history_entries = History.read(context)

          workspace_file = nil
          entry = nil
          session_id = nil

          if options[:recent]
            raise(Error, 'Do not provide a session argument when using --recent') unless args.empty? && options[:session].nil?

            index = options[:recent].to_i
            raise(Error, '--recent expects a positive integer') unless index.positive?

            raise(Error, 'No sessions available in history.') if history_entries.empty?

            sorted = history_entries.sort_by { |record| record['timestamp'].to_s }.reverse
            entry = sorted[index - 1]
            raise(Error, "History entry ##{index} was not found.") unless entry

            workspace_file = entry['workspace']
            session_id = entry['session_id']
          else
            token = options[:session] || args.shift
            raise(Error, 'Provide a session identifier or use --recent.') if Helpers.blank?(token)

            workspace_file, entry, session_id = History.resolve_workspace_from_token(context, token, history_entries)
          end

          workspace_file = File.expand_path(workspace_file) if workspace_file
          raise(Error, 'Workspace path was not recorded for this session.') if workspace_file.nil?
          raise(Error, "Workspace file not found: #{workspace_file}") unless File.exist?(workspace_file)

          manifest = History.manifest_for(context, session_id)
          base_entry = entry || {
            'session_id' => session_id,
            'workspace' => workspace_file,
            'timestamp' => manifest&.fetch('created_at', nil)
          }

          snapshot = History.session_snapshot(context, base_entry, manifest)
          block = SessionRenderer.session_block_lines(context, snapshot, 9)
          Output.print_info_block(context, block)

          context[:stdout].puts workspace_file if options[:print]

          Workspace.launch_editor(context, workspace_file) unless context[:no_open] || options[:print]
        end

        def parse_options(context, args)
          options = {
            session: nil,
            recent: nil,
            print: false
          }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: #{context[:command_name]} open [options] <session-id>"
            opts.on('--session ID', 'Session identifier to open') { |value| options[:session] = value }
            opts.on('--recent N', Integer, 'Open the Nth most recent session (1 = latest)') { |value| options[:recent] = value }
            opts.on('--print', 'Print workspace path without launching editor') { options[:print] = true }
            opts.on('--no-open', 'Skip launching VS Code after resolving workspace') { context[:no_open] = true }
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
