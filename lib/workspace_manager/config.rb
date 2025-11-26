# frozen_string_literal: true

require 'json'

module WorkspaceManager
  class Config
    DEFAULT_CONFIG_PATH = File.expand_path('~/.config/workspace-manager/config.json')
    DEFAULT_REPO_CONFIG_PATH = File.expand_path('~/.config/workspace-manager/repos.json')

    class LoadError < StandardError
      attr_reader :path

      def initialize(message, path: nil)
        super(message)
        @path = path
      end
    end

    class MissingConfig < LoadError; end
    class MissingSetting < LoadError; end

    attr_reader :env

    def initialize(env: ENV, config_path: nil)
      @env = env
      @config_path = config_path
    end

    def worktrees_root
      expand_path(fetch_required_path('WORKSPACE_MANAGER_WORKTREES_ROOT', 'worktrees_root'))
    end

    def workspaces_root
      expand_path(fetch_required_path('WORKSPACE_MANAGER_WORKSPACES_ROOT', 'workspaces_root'))
    end

    def history_file
      expand_path(fetch_required_path('WORKSPACE_MANAGER_HISTORY_FILE', 'history_file'))
    end

    def repo_config
      expand_path(fetch_required_path('WORKSPACE_MANAGER_REPO_CONFIG', 'repo_config'))
    end

    class ProhibitedGlob < LoadError; end

    def search_patterns
      @search_patterns ||= begin
        value = env['WORKSPACE_MANAGER_SEARCH_PATTERNS']
        value = config_list('search', 'patterns') if value.nil?
        patterns = normalize_list(value, [])
        patterns.each do |pattern|
          if pattern.match?(%r{/.+\*\*/}) || pattern.match?(%r{\*\*})
            raise ProhibitedGlob.new("Prohibited glob pattern detected: '#{pattern}'. Patterns containing '/**/' or '**' are not allowed.")
          end
        end
        patterns
      end
    end

    def dry_run?
      truthy?(env['WORKSPACE_MANAGER_DRY_RUN'])
    end

    def verbose?
      truthy?(env['WORKSPACE_MANAGER_VERBOSE'])
    end

    def config_path
      @config_path ||= expand_path(env.fetch('WORKSPACE_MANAGER_CONFIG_FILE', DEFAULT_CONFIG_PATH))
    end

    def to_h
      JSON.parse(JSON.generate(config_data))
    end

    private

    def fetch_required_path(env_key, config_key, default: nil)
      raw = env[env_key]
      raw = config_value(config_key) if raw.nil?
      raw = default if raw.nil?

      unless raw
        raise MissingSetting.new("Missing setting '#{config_key}'. Run '#{command_name_for_messages} setup' to configure workspace-manager.", path: config_path)
      end

      raw
    end

    def expand_path(path)
      File.expand_path(path)
    end

    def truthy?(value)
      return false if value.nil?

      %w[1 true yes on].include?(value.strip.downcase)
    end

    def config_value(*keys)
      keys.reduce(config_data) do |memo, key|
        case memo
        when Hash
          memo[key.to_s]
        else
          nil
        end
      end
    end

    def config_list(*keys)
      config_value(*keys)
    end

    def config_data
      return @config_data if defined?(@config_data)

      path = config_path
      unless File.file?(path)
        raise MissingConfig.new("Config file #{path} is missing. Run '#{command_name_for_messages} setup' to create it.", path: path)
      end

      contents = File.read(path)
      contents = '{}' if contents.strip.empty?
      parsed = JSON.parse(contents)
      unless parsed.is_a?(Hash)
        raise LoadError.new("Config file #{path} must contain a JSON object at the top level.", path: path)
      end

      @config_data = parsed
    rescue JSON::ParserError => e
      raise LoadError.new("Failed to parse #{path}: #{e.message}", path: path)
    end

    def normalize_list(raw, default)
      case raw
      when nil
        default
      when Array
        normalized = raw.flat_map do |entry|
          next [] if entry.nil?
          value = entry.to_s.strip
          value.empty? ? [] : [value]
        end
        normalized = normalized.uniq
        normalized.empty? ? default : normalized
      else
        values = raw.to_s.split(/[,:;]/).map(&:strip).reject(&:empty?)
        values = values.uniq
        values.empty? ? default : values
      end
    end

    def command_name_for_messages
      value = env['WORKSPACE_MANAGER_COMMAND_NAME']
      return 'wm' if value.nil?

      trimmed = value.to_s.strip
      trimmed.empty? ? 'wm' : trimmed
    end
  end
end
