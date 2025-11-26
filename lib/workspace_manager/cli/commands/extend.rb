# frozen_string_literal: true

require 'optparse'
require 'json'
require 'time'

module WorkspaceManager
  module CLI
    module Commands
      module Extend
        module_function

        def call(context, args)
          options = parse_options(context, args)

          session_id = options[:session] || args.shift
          raise(Error, 'Provide a session identifier to extend.') if Helpers.blank?(session_id)

          repos = args
          extra_folders = Array(context[:extra_folders])
          if repos.empty? && extra_folders.empty?
            raise(Error, 'Provide at least one repo or folder to extend session.')
          end

          manifest_file = File.join(context[:workspaces_root], "#{session_id}.json")
          workspace_file = File.join(context[:workspaces_root], "#{session_id}.code-workspace")

          unless File.exist?(manifest_file)
            raise(Error, "Manifest not found for session: #{session_id}")
          end

          unless File.exist?(workspace_file)
            raise(Error, "Workspace file not found for session: #{session_id}")
          end

          manifest = JSON.parse(File.read(manifest_file))
          slug = manifest['slug']
          feature_name = manifest['feature']

          if Helpers.blank?(slug)
            raise(Error, "Manifest for #{session_id} missing slug; unable to extend.") if Helpers.blank?(feature_name)

            slug = Workspace.slugify(feature_name)
          end

          context[:feature_name] = feature_name

          existing_repo_entries = manifest['repos']
          existing_repo_names = if existing_repo_entries.is_a?(Array)
                                  existing_repo_entries.filter_map { |entry| entry['repo'] }
                                else
                                  []
                                end

          duplicates = repos.select { |repo| existing_repo_names.include?(repo) }
          unless duplicates.empty?
            raise(Error, "Repos already part of session: #{duplicates.uniq.join(', ')}")
          end

          Runtime.ensure_directories(context)
          resolved_map = {}

          unless repos.empty?
            Runtime.require_command(context, 'git')
            resolved_pairs = Repo.resolve(context, repos)
            resolved_map = resolved_pairs.to_h
          end

          workspace_data = JSON.parse(File.read(workspace_file))
          existing_folders = workspace_data['folders'] || []
          existing_paths = existing_folders.filter_map { |folder| folder['path'] }

          manifest['repos'] ||= []
          manifest['folders'] ||= []
          new_manifest_entries = []
          new_manifest_folders = []
          new_folders = []

          resolved_map.each do |repo, repo_path|
            worktree_path = File.join(context[:worktrees_root], repo, slug)
            if existing_paths.include?(worktree_path)
              raise(Error, "Worktree already present for repo '#{repo}'.")
            end

            base_branch = Workspace.base_for(context, repo)
            branch_name = "feature/#{slug}"

            Runtime.ensure_directory(context, File.dirname(worktree_path))

            final_branch = Repo.prepare_worktree(context, repo, repo_path, worktree_path, base_branch, branch_name)

            new_folders << { 'path' => worktree_path, 'name' => repo }
            new_manifest_entries << {
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
            if existing_paths.include?(path)
              raise(Error, "Folder already present in workspace: #{path}")
            end

            new_folders << { 'path' => path, 'name' => name }
            new_manifest_folders << { 'name' => name, 'path' => path }
          end

          workspace_data['folders'] = existing_folders + new_folders
          workspace_data['settings'] ||= {}

          manifest['repos'].concat(new_manifest_entries)
          manifest['folders'].concat(new_manifest_folders)
          manifest['updated_at'] = Time.now.utc.iso8601

          Workspace.write_json(context, workspace_file, workspace_data)
          Workspace.write_json(context, manifest_file, manifest)

          Workspace.launch_editor(context, workspace_file)

          summary_tokens = []
          summary_tokens << "repos: #{resolved_map.keys.join(', ')}" unless resolved_map.empty?
          summary_tokens << "folders: #{new_manifest_folders.map { |f| f['path'] }.join(', ')}" unless new_manifest_folders.empty?
          Output.log(context, :success, "Session #{session_id} extended with #{summary_tokens.join(' and ')}")
        rescue JSON::ParserError => e
          raise(Error, "Session manifest for '#{session_id}' could not be parsed: #{e.message}")
        end

        def parse_options(context, args)
          options = { session: nil }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: #{context[:command_name]} extend [options] <session-id> repoA [repoB ...]"
            opts.on('--session ID', 'Existing session identifier to extend') { |value| options[:session] = value }
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
            opts.on('--checkout-existing', 'Reuse an existing branch/worktree if found') { context[:checkout_existing] = true }
            opts.on('--dry-run', 'Print actions without executing them') { context[:dry_run] = true }
            opts.on('--no-open', 'Skip launching VS Code after updating workspace') { context[:no_open] = true }
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
