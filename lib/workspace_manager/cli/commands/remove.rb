# frozen_string_literal: true

require 'optparse'
require 'fileutils'

module WorkspaceManager
  module CLI
    module Commands
      module Remove
        module_function

        def call(context, args)
          options = parse_options(context, args)

          session_id = options[:session_id] || args.shift
          raise(Error, 'Provide a session identifier to remove.') if Helpers.blank?(session_id)

          workspaces_root = context[:workspaces_root]
          archive_dir = File.join(workspaces_root, 'archive')

          manifest_candidates = [
            File.join(workspaces_root, "#{session_id}.json"),
            File.join(archive_dir, "#{session_id}.json")
          ]
          workspace_candidates = [
            File.join(workspaces_root, "#{session_id}.code-workspace"),
            File.join(archive_dir, "#{session_id}.code-workspace")
          ]
          session_dir_candidates = [
            File.join(workspaces_root, session_id),
            File.join(archive_dir, session_id)
          ]

          manifest_path = manifest_candidates.find { |path| File.exist?(path) }

          manifest = nil
          if manifest_path
            begin
              manifest = JSON.parse(File.read(manifest_path))
            rescue JSON::ParserError => e
              Output.log(context, :warn, "Failed to parse manifest #{manifest_path}: #{e.message}")
            end
          else
            Output.log(context, :warn, "Manifest not found for session: #{session_id}. Proceeding with deletion using history only.")
          end

          repos = manifest.is_a?(Hash) ? manifest['repos'] : []
          repos = [] unless repos.is_a?(Array)

          history_entries = History.read(context)
          history_data = nil
          history_list = []
          if context[:history_file] && File.exist?(context[:history_file])
            begin
              history_data = JSON.parse(File.read(context[:history_file]))
              history_list = history_data['history'] if history_data.is_a?(Hash)
            rescue JSON::ParserError => e
              Output.log(context, :warn, "Failed to parse history file: #{e.message}")
            end
          end
          history_list = [] unless history_list.is_a?(Array)

          entry = History.find_history_entry_by_session(history_list, session_id)
          if entry.nil? && manifest_path.nil?
            raise(Error, "Session '#{session_id}' not found in history or manifests.")
          end

          # Remove worktrees
          repos.each do |repo|
            worktree = repo['worktree']
            if worktree && Dir.exist?(worktree)
              Output.log(context, :info, "Removing worktree: #{worktree}")
              FileUtils.rm_rf(worktree) unless context[:dry_run]
            end

            cleanup_branch(context, repo)
          end

          # Remove workspace and notes
          (workspace_candidates + manifest_candidates + session_dir_candidates).each do |item|
            if File.exist?(item) || Dir.exist?(item)
              Output.log(context, :info, "Deleting #{item}")
              FileUtils.rm_rf(item) unless context[:dry_run]
            end
          end

          # Remove from history file if present
          if context[:history_file] && !history_list.empty?
            before = history_list.size
            history_list.reject! { |item| item['session_id'] == session_id }
            if history_list.size < before
              unless context[:dry_run]
                history_data ||= {}
                history_data['history'] = history_list
                File.write(context[:history_file], JSON.pretty_generate(history_data) + "\n")
              end
              Output.log(context, :info, "Removed session #{session_id} from history.")
            end
          end

          Output.log(context, :success, "Session #{session_id} fully removed.")
        end

        def cleanup_branch(context, repo)
          branch = repo.is_a?(Hash) ? repo['branch'] : nil
          repo_root = repo.is_a?(Hash) ? repo['root'] : nil
          base_branch = repo.is_a?(Hash) ? repo['base'] : nil

          return if Helpers.blank?(branch) || Helpers.blank?(repo_root)
          return if !Helpers.blank?(base_branch) && branch == base_branch

          repo_name = repo['repo'] || repo_root

          if context[:dry_run]
            Output.log(context, :info, "Dry-run: would delete branch #{branch} in #{repo_name}")
            return
          end

          unless File.directory?(repo_root)
            Output.log(context, :warn, "Repository root missing for branch cleanup: #{repo_root}")
            return
          end

          unless Runtime.branch_exists?(context, repo_root, branch)
            Output.log(context, :debug, "Branch #{branch} already absent in #{repo_name}")
            return
          end

          begin
            Runtime.run_cmd(context, 'git', '-C', repo_root, 'worktree', 'prune')
          rescue WorkspaceManager::Error => e
            Output.log(context, :warn, "Failed to prune worktrees for #{repo_name}: #{e.message}")
          end

          begin
            Runtime.run_cmd(context, 'git', '-C', repo_root, 'branch', '-D', branch)
            Output.log(context, :info, "Deleted branch #{branch} in #{repo_name}")
          rescue WorkspaceManager::Error => e
            Output.log(context, :warn, "Failed to delete branch #{branch} in #{repo_name}: #{e.message}")
          end
        end

        def parse_options(context, args)
          options = { session_id: nil }
          parser = OptionParser.new do |opts|
            opts.banner = "Usage: #{context[:command_name]} remove <session-id>"
            opts.on('--session ID', 'Session identifier to remove') { |value| options[:session_id] = value }
            opts.on('--dry-run', 'Print actions without executing them') { context[:dry_run] = true }
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
