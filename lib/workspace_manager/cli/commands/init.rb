# frozen_string_literal: true

require 'optparse'

module WorkspaceManager
  module CLI
    module Commands
      module Init
        module_function

        def call(context, args)
          repos = parse_options(context, args)
          raise(Error, '--feature is required') if Helpers.blank?(context[:feature_name])
          raise(Error, 'Provide at least one repo argument') if repos.empty?

          slug = Workspace.slugify(context[:feature_name])
          primary = context[:primary_repo] || repos.first

          Runtime.ensure_directories(context)
          Runtime.require_command(context, 'git')

          resolved_pairs = Repo.resolve(context, repos)
          resolved_map = resolved_pairs.to_h

          extra_folders = Array(context[:extra_folders])

          unless resolved_map.key?(primary)
            raise(Error, "Primary repo '#{primary}' was not among the resolved repositories")
          end

          tail_repos = resolved_map.keys.reject { |name| name == primary }
          session_id = Workspace.build_session_id(slug, primary, tail_repos)

          workspace_file = File.join(context[:workspaces_root], "#{session_id}.code-workspace")
          manifest_file = File.join(context[:workspaces_root], "#{session_id}.json")
          session_dir = File.join(context[:workspaces_root], session_id)

          Runtime.ensure_directory(context, session_dir)

          workspace_folders = []
          manifest_repo_entries = []
          manifest_folder_entries = []

          resolved_map.each do |repo, repo_path|
            worktree_path = File.join(context[:worktrees_root], repo, slug)
            base_branch = Workspace.base_for(context, repo)
            branch_name = "feature/#{slug}"

            Runtime.ensure_directory(context, File.dirname(worktree_path))

            final_branch = branch_name.dup
            if File.directory?(worktree_path) && !Dir.empty?(worktree_path)
              Output.log(context, :warn, "Worktree path already exists: #{worktree_path}")
            else
              final_branch = Repo.prepare_worktree(context, repo, repo_path, worktree_path, base_branch, branch_name)
            end

            workspace_folders << { repo: repo, path: worktree_path, name: repo }
            manifest_repo_entries << {
              'repo' => repo,
              'root' => repo_path,
              'worktree' => worktree_path,
              'branch' => final_branch,
              'base' => base_branch
            }
          end

          extra_folders.each do |folder|
            path = folder[:path]
            name = folder[:name] || File.basename(path)
            workspace_folders << { path: path, name: name }
            manifest_folder_entries << {
              'name' => name,
              'path' => path
            }
          end

          Workspace.write_workspace_file(context, workspace_file, workspace_folders)
          Workspace.write_manifest_file(context, manifest_file, session_id, slug, manifest_repo_entries, manifest_folder_entries)
          History.append(context, session_id, workspace_file)
          Workspace.prefill_notes(context, session_dir)
          Workspace.launch_editor(context, workspace_file)

          Output.log(context, :success, "Workspace ready: #{workspace_file}")
          Output.log(context, :success, "Worktrees: #{workspace_folders.map { |f| f[:path] }.join(', ')}")
        end

        def parse_options(context, args)
          parser = OptionParser.new do |opts|
            opts.banner = "Usage: #{context[:command_name]} init --feature \"story\" repoA [repoB ...]"
            opts.on('--feature NAME', 'Feature or story name (required)') { |value| context[:feature_name] = value }
            opts.on('--primary NAME', 'Primary repo anchor (defaults to first)') { |value| context[:primary_repo] = value }
            opts.on('--base VALUE', 'Base branch (global or repo:branch). Repeatable.') do |value|
              if value.include?(':')
                repo, branch = value.split(':', 2)
                context[:base_overrides][repo] = branch
              else
                context[:default_base] = value
              end
            end
            opts.on('--folder SPEC', 'Add an existing folder without creating a worktree') do |value|
              context[:extra_folders] ||= []
              context[:extra_folders] << Helpers.folder_entry(context, value)
            end
            opts.on('--notes TEXT', 'Prefill notes.md with supplied text') { |value| context[:notes_text] = value }
            opts.on('--checkout-existing', 'Reuse an existing branch/worktree if found') { context[:checkout_existing] = true }
            opts.on('--dry-run', 'Print actions without executing them') { context[:dry_run] = true }
            opts.on('--no-open', 'Skip launching VS Code after setup') { context[:no_open] = true }
            opts.on('--verbose', '-v', 'Show verbose output') { context[:verbose] = true }
            opts.on('-h', '--help', 'Show this help') do
              context[:stdout].puts opts
              exit
            end
          end

          parser.parse!(args)
          args
        end
      end
    end
  end
end
