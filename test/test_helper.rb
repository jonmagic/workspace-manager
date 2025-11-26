# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'stringio'
require 'fileutils'
require_relative '../lib/workspace_manager'

class TTYStringIO < StringIO
	def tty?
		true
	end
end

class NonTTYStringIO < StringIO
	def tty?
		false
	end
end

# Shared test helpers for CLI and command tests
module WorkspaceManagerTestHelpers
	class StubConfig
		attr_reader :worktrees_root, :workspaces_root, :history_file, :repo_config

		def initialize(root)
			@worktrees_root = File.join(root, 'worktrees')
			@workspaces_root = File.join(root, 'workspaces')
			@history_file = File.join(root, 'history.json')
			@repo_config = File.join(root, 'repos.json')
			FileUtils.mkdir_p(@worktrees_root)
			FileUtils.mkdir_p(@workspaces_root)
		end

		def search_patterns
			[]
		end

		def dry_run?
			true
		end

		def verbose?
			false
		end
	end

	class StubRepoLocator
		def initialize(resolution = {})
			@resolution = resolution
		end

		def candidates(token)
			@resolution.fetch(token, [])
		end
	end

	module ContextHelper
		def build_context(argv: [], config: nil, repo_locator: nil, stdin: NonTTYStringIO.new, stdout: NonTTYStringIO.new, stderr: NonTTYStringIO.new, command_name: 'wm')
			config ||= StubConfig.new(Dir.mktmpdir('wm-context-'))
			WorkspaceManager::CLI::Context.build(
				argv: argv,
				config: config,
				repo_locator: repo_locator,
				stdin: stdin,
				stdout: stdout,
				stderr: stderr,
				default_base: WorkspaceManager::CLI::DEFAULT_BASE_BRANCH,
				color_map: WorkspaceManager::CLI::COLOR_MAP,
				command_name: command_name
			)
		end
	end
end

Minitest::Spec.include(WorkspaceManagerTestHelpers::ContextHelper)
