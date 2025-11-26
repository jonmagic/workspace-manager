# frozen_string_literal: true

module WorkspaceManager
  module CLI
    module Context
      module_function

      def build(argv:, config:, repo_locator:, stdin:, stdout:, stderr:, default_base:, color_map:, command_name: 'wm')
        {
          argv: argv.dup,
          config: config,
          repo_locator: repo_locator || RepoLocator.new(config),
          stdin: stdin,
          stdout: stdout,
          stderr: stderr,
          worktrees_root: config.worktrees_root,
          workspaces_root: config.workspaces_root,
          history_file: config.history_file,
          repo_config: config.repo_config,
          dry_run: config.dry_run?,
          checkout_existing: false,
          no_open: false,
          verbose: config.verbose?,
          notes_text: nil,
          feature_name: nil,
          primary_repo: nil,
          default_base: default_base,
          base_overrides: {},
          color_map: color_map,
          extra_folders: [],
          command_name: command_name
        }
      end

      def interactive?(context)
        context[:stdin].tty?
      end
    end
  end
end
