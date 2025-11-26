# frozen_string_literal: true

module WorkspaceManager
  class RepoLocator
    def initialize(config)
      @config = config
    end

    def candidates(token)
      normalized = token.to_s.strip
      return [] if normalized.empty?

      patterns = @config.search_patterns
      results = patterns.flat_map { |pattern| resolve_pattern(pattern, normalized) }

      results.compact.reject { |path| path.include?('/worktrees/') }.uniq
    end

    private

    def resolve_pattern(pattern, token)
      matches = []
      if pattern.include?("%{repo}")
        candidate = pattern.gsub("%{repo}", token)
        matches << candidate if File.directory?(candidate)
      elsif pattern.include?("*") || pattern.include?("?") || pattern.include?("[")
        # Expand the glob, then for each match, check for subdirectory named token
        Dir.glob(pattern).each do |path|
          if File.directory?(path)
            # If the directory itself matches the token
            matches << path if File.basename(path) == token
            # If a subdirectory matches the token
            subdir = File.join(path, token)
            matches << subdir if File.directory?(subdir)
          end
        end
      else
        # If pattern is a direct path, check if its basename matches the token
        base = expand_path(pattern)
        if File.directory?(base)
          matches << base if File.basename(base) == token
          # Also check for subdirectory match
          candidate = File.join(base, token)
          matches << candidate if File.directory?(candidate)
        end
      end
      matches
    end

    def expand_path(path)
      File.expand_path(path)
    rescue ArgumentError
      path
    end
  end
end
