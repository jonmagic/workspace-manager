# frozen_string_literal: true

require 'optparse'

require_relative 'version'
require_relative 'config'
require_relative 'setup'
require_relative 'repo_locator'
require_relative 'cli/context'
require_relative 'cli/helpers'
require_relative 'cli/output'
require_relative 'cli/runtime'
require_relative 'cli/repo'
require_relative 'cli/workspace'
require_relative 'cli/history'
require_relative 'cli/session_renderer'
require_relative 'cli/commands/config'
require_relative 'cli/commands/init'
require_relative 'cli/commands/list'
require_relative 'cli/commands/open'
require_relative 'cli/commands/prune'
require_relative 'cli/commands/extend'
require_relative 'cli/commands/remove'

module WorkspaceManager
  class Error < StandardError; end

  module CLI
    DEFAULT_BASE_BRANCH = 'main'

    COLOR_MAP = {
      info: 36,
      warn: 33,
      error: 31,
      success: 32,
      debug: 90
    }.freeze

    USAGE_TEMPLATE = <<~USAGE.freeze
      Usage: %{command} <command> [options]

      Commands:
        init       Initialize workspace session and Git worktrees
        config     Show the current configuration JSON
        list       Display recent workspace sessions
        open       Launch an existing workspace session
        prune      Remove worktrees and archive workspace session
        remove     Permanently delete a workspace session and all traces
        extend     Attach additional repositories to an existing session
        setup      Interactive configuration wizard
        help       Show this message
        version    Print CLI version

      Run '%{command} <command> --help' for detailed options.
    USAGE

    module_function

    def usage_message(command_name)
      format(USAGE_TEMPLATE, command: command_name)
    end

    def determine_command_name(program_name: nil, env: ENV)
      override = env['WORKSPACE_MANAGER_COMMAND_NAME']
      return override.strip unless override.nil? || override.strip.empty?

      candidate = program_name
      candidate = Process.argv0 if candidate.nil? && Process.respond_to?(:argv0)
      candidate = $PROGRAM_NAME if candidate.nil?
      candidate = env['_'] if (candidate.nil? || candidate.strip.empty?) && env['_']

      command = candidate.to_s.strip
      command = File.basename(command) unless command.empty?
      command = 'wm' if command.nil? || command.empty?
      command
    end

    def run(argv, config: nil, repo_locator: nil, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      env = ENV
      args = argv.dup
      command_name = determine_command_name(env: env)
      env['WORKSPACE_MANAGER_COMMAND_NAME'] = command_name

      if args.first == 'setup'
        args.shift
        begin
          WorkspaceManager::Setup.run(stdin: stdin, stdout: stdout, stderr: stderr, env: env, command_name: command_name)
        rescue WorkspaceManager::Setup::NonInteractiveError => e
          stderr.puts(e.message)
          exit 1
        end
        return
      end

      attempts = 0
      begin
        effective_config = config || Config.new(env: env)
        context = Context.build(
          argv: args,
          config: effective_config,
          repo_locator: repo_locator,
          stdin: stdin,
          stdout: stdout,
          stderr: stderr,
          default_base: DEFAULT_BASE_BRANCH,
          color_map: COLOR_MAP,
          command_name: command_name
        )

        execute(context)
      rescue Config::MissingConfig => e
        if config.nil? && stdin.tty?
          success = WorkspaceManager::Setup.run(stdin: stdin, stdout: stdout, stderr: stderr, env: env, config_path: e.path, command_name: command_name)
          if success && (attempts += 1) <= 1
            config = nil
            retry
          end
        end
        stderr.puts(e.message)
        exit 1
      rescue Config::MissingSetting => e
        stderr.puts(e.message)
        stderr.puts("Run '#{command_name} setup' to update your configuration.")
        exit 1
      rescue WorkspaceManager::Setup::NonInteractiveError => e
        stderr.puts(e.message)
        exit 1
      rescue Error => e
        Output.log(context, :error, e.message)
        exit 1
      end
    end

    def execute(context)
      command = context[:argv].shift

      case command
      when nil, 'help', '-h', '--help'
        context[:stdout].puts(usage_message(context[:command_name]))
      when 'version', '--version'
        context[:stdout].puts("workspace-manager #{WorkspaceManager::VERSION}")
      when 'init'
        Commands::Init.call(context, context[:argv])
      when 'config'
        Commands::Config.call(context, context[:argv])
      when 'list'
        Commands::List.call(context, context[:argv])
      when 'open'
        Commands::Open.call(context, context[:argv])
      when 'prune'
        Commands::Prune.call(context, context[:argv])
      when 'remove'
        Commands::Remove.call(context, context[:argv])
      when 'extend'
        Commands::Extend.call(context, context[:argv])
      else
        raise(Error, "Unknown command '#{command}'. Use '#{context[:command_name]} help'.")
      end
    end
  end
end
