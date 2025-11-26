# frozen_string_literal: true

require 'json'
require 'time'

module WorkspaceManager
  module CLI
    module Workspace
      module_function

      def slugify(text)
        slug = text.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
        raise(Error, "Unable to derive slug from '#{text}'") if slug.empty?

        slug
      end

      def build_session_id(slug, primary, tail_repos)
        return "#{slug}--#{primary}" if tail_repos.empty?

        canonical_tail = tail_repos.sort.join('+')
        "#{slug}--#{primary}+#{canonical_tail}"
      end

      def base_for(context, repo)
        context[:base_overrides].fetch(repo, context[:default_base])
      end

      def write_workspace_file(context, file, folders)
        data = {
          'folders' => folders.map do |folder|
            entry = { 'path' => folder[:path] }
            entry['name'] = folder[:name] if folder[:name]
            entry
          end,
          'settings' => {}
        }

        write_json(context, file, data)
      end

      def write_manifest_file(context, file, session_id, slug, repos, folders = [])
        data = {
          'session_id' => session_id,
          'feature' => context[:feature_name],
          'slug' => slug,
          'created_at' => Time.now.utc.iso8601,
          'repos' => repos
        }

        data['folders'] = folders unless folders.nil? || folders.empty?

        write_json(context, file, data)
      end

      def write_json(context, file, data)
        if context[:dry_run]
          Output.log(context, :info, "[dry-run] Would write #{file}")
          return
        end

        Runtime.ensure_directory(context, File.dirname(file))
        File.write(file, JSON.pretty_generate(data) + "\n")
      end

      def prefill_notes(context, session_dir)
        notes_text = context[:notes_text]
        return if notes_text.nil? || notes_text.empty?
        return if context[:dry_run]

        Runtime.ensure_directory(context, session_dir)
        notes_file = File.join(session_dir, 'notes.md')
        return if File.exist?(notes_file)

        content = "# Notes\n\n#{notes_text}\n"
        File.write(notes_file, content)
      end

      def launch_editor(context, workspace_file)
        return if context[:dry_run] || context[:no_open]

        editor = Runtime.which(context, 'code-insiders') || Runtime.which(context, 'code')
        unless editor
          Output.log(context, :warn, 'VS Code CLI (code/code-insiders) not found; skipping launch.')
          return
        end

        Runtime.run_cmd(context, editor, workspace_file)
      end
    end
  end
end
