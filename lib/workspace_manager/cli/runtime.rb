# frozen_string_literal: true

require 'fileutils'
require 'shellwords'

module WorkspaceManager
  module CLI
    module Runtime
      module_function

      def ensure_directories(context)
        ensure_directory(context, context[:worktrees_root])
        ensure_directory(context, context[:workspaces_root])
        ensure_directory(context, File.dirname(context[:history_file]))
      end

      def ensure_directory(context, path)
        return if context[:dry_run]

        FileUtils.mkdir_p(path)
      end

      def run_cmd(context, *args)
        Output.log(context, :debug, "+ #{Shellwords.shelljoin(args)}")
        return true if context[:dry_run]

        system(*args) || raise(Error, "Command failed: #{Shellwords.shelljoin(args)}")
      end

      def which(_context, cmd)
        ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |dir|
          path = File.join(dir, cmd)
          return path if File.executable?(path)
        end
        nil
      end

      def require_command(context, cmd)
        return if which(context, cmd)

        raise(Error, "Missing required command '#{cmd}'. Please install it first.")
      end

      def prompt_yes_no(context, message, default: true)
        raise(Error, 'User interaction is not possible in non-interactive mode') unless Context.interactive?(context)

        suffix = default ? 'Y/n' : 'y/N'
        loop do
          context[:stdout].print "#{message} [#{suffix}]: "
          input = context[:stdin].gets
          raise(Error, 'Selection cancelled') if input.nil?

          normalized = input.strip.downcase
          return default if normalized.empty?
          return true if %w[y yes].include?(normalized)
          return false if %w[n no].include?(normalized)

          context[:stdout].puts 'Please enter y or n.'
        end
      end

      def branch_exists?(context, repo_path, branch)
        return false unless File.directory?(repo_path)

        system('git', '-C', repo_path, 'rev-parse', '--verify', branch, out: File::NULL, err: File::NULL)
      end
    end
  end
end
