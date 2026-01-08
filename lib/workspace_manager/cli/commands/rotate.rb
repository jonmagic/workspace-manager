# frozen_string_literal: true

require 'optparse'
require 'json'
require 'time'

module WorkspaceManager
  module CLI
    module Commands
      module Rotate
        module_function

        def call(context, args)
          options = parse_options(context, args)

          session_id = options[:session] || args.shift
          raise(Error, 'Provide a session identifier to rotate.') if Helpers.blank?(session_id)
          raise(Error, 'Provide a target branch name with --branch.') if Helpers.blank?(options[:branch])

          target_branch = options[:branch]
          create = options[:create]
          base_branch = options[:base]

          manifest_file = File.join(context[:workspaces_root], "#{session_id}.json")
          workspace_file = File.join(context[:workspaces_root], "#{session_id}.code-workspace")

          unless File.exist?(manifest_file)
            raise(Error, "Manifest not found for session: #{session_id}")
          end

          unless File.exist?(workspace_file)
            raise(Error, "Workspace file not found for session: #{session_id}")
          end

          manifest = JSON.parse(File.read(manifest_file))
          workspace_data = JSON.parse(File.read(workspace_file))

          repos = manifest['repos'] || []
          raise(Error, "No repos found in session manifest.") if repos.empty?

          Runtime.ensure_directories(context)
          Runtime.require_command(context, 'git')

          use_worktrunk = Worktrunk.available?(context)
          Output.log(context, :info, "Using #{use_worktrunk ? 'Worktrunk' : 'git'} for worktree management")

          rotation_timestamp = Time.now.utc.iso8601
          rotation_entry = {
            'timestamp' => rotation_timestamp,
            'branch' => target_branch,
            'previous_branch' => manifest['current_branch']
          }

          updated_repos = []
          updated_folders = []

          repos.each do |repo|
            repo_name = repo['repo']
            repo_path = repo['root']
            old_worktree = repo['worktree']
            old_branch = repo['branch']
            effective_base = base_branch || repo['base'] || context[:default_base]

            Output.log(context, :info, "Rotating #{repo_name} from #{old_branch} to #{target_branch}")

            new_worktree_path = nil

            if use_worktrunk
              # Use Worktrunk for worktree management
              begin
                new_worktree_path = Worktrunk.switch(context, repo_path, target_branch, create: create, base: effective_base)
              rescue Error => e
                Output.log(context, :warn, "Worktrunk switch failed for #{repo_name}: #{e.message}")
                # Fall back to git
                new_worktree_path = git_switch_worktree(context, repo_name, repo_path, target_branch, create, effective_base)
              end
            else
              # Use git directly
              new_worktree_path = git_switch_worktree(context, repo_name, repo_path, target_branch, create, effective_base)
            end

            if new_worktree_path.nil?
              raise(Error, "Failed to determine worktree path for #{repo_name} on branch #{target_branch}")
            end

            updated_repos << {
              'repo' => repo_name,
              'root' => repo_path,
              'worktree' => new_worktree_path,
              'branch' => target_branch,
              'base' => effective_base,
              'previous_branch' => old_branch
            }

            updated_folders << {
              'path' => new_worktree_path,
              'name' => repo_name
            }
          end

          # Preserve any extra folders that aren't repos
          manifest_folders = manifest['folders'] || []
          manifest_folders.each do |folder|
            path = folder['path']
            name = folder['name']
            updated_folders << { 'path' => path, 'name' => name }
          end

          # Update workspace file folders
          workspace_data['folders'] = updated_folders

          # Update manifest
          manifest['repos'] = updated_repos
          manifest['current_branch'] = target_branch
          manifest['rotation_history'] ||= []
          manifest['rotation_history'] << rotation_entry
          manifest['updated_at'] = rotation_timestamp

          Workspace.write_json(context, workspace_file, workspace_data)
          Workspace.write_json(context, manifest_file, manifest)

          Output.log(context, :success, "Session #{session_id} rotated to branch #{target_branch}")
          Output.log(context, :info, "Worktrees: #{updated_folders.map { |f| f['path'] }.join(', ')}")

          Workspace.launch_editor(context, workspace_file) unless context[:no_open]
        end

        def git_switch_worktree(context, repo_name, repo_path, branch, create, base)
          slug = Workspace.slugify(branch)
          worktree_path = File.join(context[:worktrees_root], repo_name, slug)

          # Check if worktree already exists
          if File.directory?(worktree_path) && !Dir.empty?(worktree_path)
            Output.log(context, :info, "Worktree already exists for #{repo_name} at #{worktree_path}")
            return worktree_path
          end

          Runtime.ensure_directory(context, File.dirname(worktree_path))

          branch_exists = Runtime.branch_exists?(context, repo_path, branch)

          if create && !branch_exists
            # Create new branch and worktree
            Runtime.run_cmd(context, 'git', '-C', repo_path, 'fetch', '--all', '--prune')
            Runtime.run_cmd(context, 'git', '-C', repo_path, 'worktree', 'add', '-b', branch, worktree_path, base)
          elsif branch_exists
            # Check out existing branch
            Runtime.run_cmd(context, 'git', '-C', repo_path, 'worktree', 'add', worktree_path, branch)
          else
            raise(Error, "Branch #{branch} does not exist for #{repo_name}. Use --create to create it.")
          end

          worktree_path
        end

        def parse_options(context, args)
          options = {
            session: nil,
            branch: nil,
            create: false,
            base: nil
          }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: #{context[:command_name]} rotate --session <id> --branch <branch> [options]"
            opts.on('--session ID', 'Session identifier to rotate') { |value| options[:session] = value }
            opts.on('--branch BRANCH', 'Target branch name') { |value| options[:branch] = value }
            opts.on('--create', 'Create the branch if it does not exist') { options[:create] = true }
            opts.on('--base BRANCH', 'Base branch for new branches') { |value| options[:base] = value }
            opts.on('--dry-run', 'Print actions without executing them') { context[:dry_run] = true }
            opts.on('--no-open', 'Skip launching VS Code after rotation') { context[:no_open] = true }
            opts.on('--verbose', '-v', 'Show verbose output') { context[:verbose] = true }
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
