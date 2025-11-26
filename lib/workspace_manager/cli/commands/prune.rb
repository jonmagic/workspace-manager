# frozen_string_literal: true

require 'optparse'
require 'fileutils'

module WorkspaceManager
  module CLI
    module Commands
      module Prune
        module_function

        def call(context, args)
          options = parse_options(context, args)

          session_id = options[:session_id] || args.shift
          raise(Error, 'Provide a session identifier to prune.') if Helpers.blank?(session_id)

          manifest_file = File.join(context[:workspaces_root], "#{session_id}.json")
          workspace_file = File.join(context[:workspaces_root], "#{session_id}.code-workspace")
          session_dir = File.join(context[:workspaces_root], session_id)
          archive_dir = File.join(context[:workspaces_root], 'archive')
          archive_session_dir = File.join(archive_dir, session_id)

          unless File.exist?(manifest_file)
            raise(Error, "Manifest not found for session: #{session_id}")
          end

          manifest = JSON.parse(File.read(manifest_file))
          repos = manifest['repos'] || []

          # Remove worktrees
          repos.each do |repo|
            worktree = repo['worktree']
            if worktree && Dir.exist?(worktree)
              Output.log(context, :info, "Removing worktree: #{worktree}")
              FileUtils.rm_rf(worktree) unless context[:dry_run]
            end

            cleanup_branch(context, repo)
          end

          # Archive workspace and notes
          FileUtils.mkdir_p(archive_dir) unless context[:dry_run]
          [workspace_file, manifest_file, session_dir].each do |item|
            next unless File.exist?(item) || Dir.exist?(item)
            dest = File.join(archive_dir, File.basename(item))
            Output.log(context, :info, "Archiving #{item} to #{dest}")
            FileUtils.mv(item, dest) unless context[:dry_run]
          end

          Output.log(context, :success, "Session #{session_id} pruned and archived.")
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
            opts.banner = "Usage: #{context[:command_name]} prune <session-id>"
            opts.on('--session ID', 'Session identifier to prune') { |value| options[:session_id] = value }
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
