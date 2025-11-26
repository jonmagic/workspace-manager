# frozen_string_literal: true

require 'json'
require 'fileutils'

module WorkspaceManager
  class Setup
    DEFAULTS = {
      'worktrees_root' => '~/code/worktrees',
      'workspaces_root' => '~/code/workspaces',
      'history_file' => '~/.config/workspace-manager/history.json',
      'repo_config' => WorkspaceManager::Config::DEFAULT_REPO_CONFIG_PATH,
      'search_patterns' => ['~/code/path/to/project', '~/code/<owner>/*', '~/code/**/*']
    }.freeze

    class Cancelled < StandardError; end
    class NonInteractiveError < StandardError; end

    def self.run(stdin:, stdout:, stderr:, env:, config_path: nil, command_name: nil)
      command_name ||= env['WORKSPACE_MANAGER_COMMAND_NAME'] || 'wm'
      unless stdin.tty?
        raise NonInteractiveError, "Setup requires an interactive terminal. Run `#{command_name} setup` from a TTY."
      end

      resolved_path = resolve_config_path(env, config_path)
      ensure_config_directory(resolved_path)

      existing = read_existing(resolved_path)
      defaults = build_defaults(existing)

      stdout.puts 'workspace-manager interactive setup'
      stdout.puts '-' * 40

      worktrees = prompt_value(stdin, stdout, 'Worktrees root', defaults['worktrees_root'])
      workspaces = prompt_value(stdin, stdout, 'Workspaces root', defaults['workspaces_root'])
      history = prompt_value(stdin, stdout, 'History file', defaults['history_file'])
      repo_config = prompt_value(stdin, stdout, 'Repository registry file', defaults['repo_config'])
      search_patterns = prompt_list(stdin, stdout, 'Search patterns (comma separated)', defaults['search_patterns'])

      config = {
        'worktrees_root' => worktrees,
        'workspaces_root' => workspaces,
        'history_file' => history,
        'repo_config' => repo_config,
        'search' => {
          'patterns' => search_patterns
        }
      }

      File.write(resolved_path, JSON.pretty_generate(config) + "\n")
      ensure_repo_registry(repo_config)

      stdout.puts
      stdout.puts "Configuration written to #{resolved_path}"
  stdout.puts "You can rerun `#{command_name} setup` anytime to update these values."
      true
    rescue Cancelled
      stderr.puts 'Setup cancelled. No changes were made.'
      false
    end

    def self.resolve_config_path(env, explicit_path)
      raw = explicit_path || env['WORKSPACE_MANAGER_CONFIG_FILE'] || WorkspaceManager::Config::DEFAULT_CONFIG_PATH
      File.expand_path(raw)
    end

    def self.ensure_config_directory(path)
      FileUtils.mkdir_p(File.dirname(path))
    end

    def self.read_existing(path)
      return {} unless File.file?(path)

      contents = File.read(path)
      return {} if contents.strip.empty?

      parsed = JSON.parse(contents)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def self.build_defaults(existing)
      search = existing.fetch('search', {})
      patterns = normalize_list(search['patterns'])

      {
        'worktrees_root' => existing['worktrees_root'] || DEFAULTS['worktrees_root'],
        'workspaces_root' => existing['workspaces_root'] || DEFAULTS['workspaces_root'],
        'history_file' => existing['history_file'] || DEFAULTS['history_file'],
        'repo_config' => existing['repo_config'] || DEFAULTS['repo_config'],
        'search_patterns' => patterns || DEFAULTS['search_patterns']
      }
    end

    def self.normalize_list(value)
      case value
      when nil
        nil
      when Array
        cleaned = value.map { |entry| entry.to_s.strip }.reject(&:empty?)
        cleaned unless cleaned.empty?
      else
        values = value.to_s.split(/[,:;]/).map(&:strip).reject(&:empty?)
        values unless values.empty?
      end
    end

    def self.prompt_value(stdin, stdout, label, default)
      loop do
        stdout.print(prompt_text(label, default))
        stdout.flush
        input = stdin.gets
        raise Cancelled if input.nil?

        normalized = input.strip
        return default if normalized.empty? && default
        return normalized unless normalized.empty?

        stdout.puts 'Please provide a value.'
      end
    end

    def self.prompt_list(stdin, stdout, label, default_values)
      default_display = default_values.join(', ')
      loop do
        stdout.print(prompt_text(label, default_display))
        stdout.flush
        input = stdin.gets
        raise Cancelled if input.nil?

        normalized = input.strip
        normalized = default_display if normalized.empty?

        values = normalized.split(/[,:;]/).map(&:strip).reject(&:empty?)
        return values unless values.empty?

        stdout.puts 'Please provide at least one value or accept the default.'
      end
    end

    def self.prompt_text(label, default)
      if default && !default.to_s.empty?
        "#{label} [#{default}]: "
      else
        "#{label}: "
      end
    end

    def self.ensure_repo_registry(repo_config_path)
      expanded = File.expand_path(repo_config_path)
      FileUtils.mkdir_p(File.dirname(expanded))
      return if File.exist?(expanded)

      File.write(expanded, "{}\n")
    end

    private_class_method :resolve_config_path, :ensure_config_directory, :read_existing,
                         :build_defaults, :normalize_list, :prompt_value, :prompt_list,
                         :prompt_text, :ensure_repo_registry
  end
end
