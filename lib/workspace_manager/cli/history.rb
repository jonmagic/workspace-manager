# frozen_string_literal: true

require 'json'
require 'time'

module WorkspaceManager
  module CLI
    module History
      module_function

      def append(context, session_id, workspace_file)
        return if context[:dry_run]

        Runtime.ensure_directory(context, File.dirname(context[:history_file]))

        history = if File.exist?(context[:history_file])
                    JSON.parse(File.read(context[:history_file]))
                  else
                    { 'history' => [] }
                  end

        history['history'] ||= []
        history['history'] << {
          'session_id' => session_id,
          'workspace' => workspace_file,
          'timestamp' => Time.now.utc.iso8601
        }

        File.write(context[:history_file], JSON.pretty_generate(history) + "\n")
      rescue JSON::ParserError
        Output.log(context, :warn, 'History file was corrupt; recreating it.')
        history = {
          'history' => [{
            'session_id' => session_id,
            'workspace' => workspace_file,
            'timestamp' => Time.now.utc.iso8601
          }]
        }
        File.write(context[:history_file], JSON.pretty_generate(history) + "\n")
      end

      def read(context)
        return [] unless File.exist?(context[:history_file])

        data = JSON.parse(File.read(context[:history_file]))
        entries = data['history']
        return [] unless entries.is_a?(Array)

        entries
      rescue JSON::ParserError => e
        Output.log(context, :warn, "History file was corrupt (#{e.message}); ignoring it.")
        []
      end

      def manifest_for(context, session_id)
        file = File.join(context[:workspaces_root], "#{session_id}.json")
        return nil unless File.exist?(file)

        JSON.parse(File.read(file))
      rescue JSON::ParserError => e
        Output.log(context, :warn, "Manifest for #{session_id} could not be parsed: #{e.message}")
        nil
      end

      def session_active?(context, manifest, entry)
        if manifest.is_a?(Hash)
          repos = manifest['repos']
          if repos.is_a?(Array)
            repos.each do |repo|
              worktree = repo['worktree']
              return true if worktree && Dir.exist?(worktree)
            end
          end
        end

        workspace = entry['workspace']
        return true if workspace && File.exist?(workspace)

        false
      end

      def session_snapshot(context, entry, manifest)
        repos = []

        if manifest.is_a?(Hash)
          repo_entries = manifest['repos']
          if repo_entries.is_a?(Array)
            repos = repo_entries.map do |repo|
              {
                'repo' => repo['repo'],
                'branch' => repo['branch'],
                'base' => repo['base'],
                'worktree' => repo['worktree']
              }
            end
          end
        end

        {
          'session_id' => entry['session_id'],
          'timestamp' => entry['timestamp'],
          'workspace' => entry['workspace'],
          'status' => session_active?(context, manifest, entry) ? 'active' : 'stale',
          'repos' => repos
        }
      end

      def resolve_workspace_from_token(context, token, history_entries)
        identifier = token.to_s.strip
        raise(Error, 'Provide a session identifier.') if identifier.empty?

        entries = history_entries || []

        expanded = File.expand_path(identifier)
        if File.file?(expanded)
          entry = find_history_entry_by_workspace(entries, expanded)
          session_id = entry ? entry['session_id'] : File.basename(expanded, '.code-workspace')
          return [expanded, entry, session_id]
        end

        entry = find_history_entry_by_session(entries, identifier)
        if entry && entry['workspace'] && File.exist?(entry['workspace'])
          return [entry['workspace'], entry, entry['session_id']]
        end

        candidate = File.join(context[:workspaces_root], identifier)
        candidate += '.code-workspace' unless candidate.end_with?('.code-workspace')
        candidate = File.expand_path(candidate)
        if File.exist?(candidate)
          entry = find_history_entry_by_workspace(entries, candidate)
          session_id = entry ? entry['session_id'] : File.basename(candidate, '.code-workspace')
          return [candidate, entry, session_id]
        end

        raise(Error, "Unable to locate workspace for '#{identifier}'.")
      end

      def find_history_entry_by_session(history_entries, session_id)
        (history_entries || []).reverse_each do |item|
          return item if item['session_id'] == session_id
        end
        nil
      end

      def find_history_entry_by_workspace(history_entries, workspace_path)
        normalized = File.expand_path(workspace_path)
        (history_entries || []).reverse_each do |item|
          next unless item['workspace']
          return item if File.expand_path(item['workspace']) == normalized
        end
        nil
      end
    end
  end
end
