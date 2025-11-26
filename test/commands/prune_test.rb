# frozen_string_literal: true

require_relative '../test_helper'
require 'json'

describe WorkspaceManager::CLI::Commands::Prune do
	let(:root) { Dir.mktmpdir('wm-prune-') }
	let(:config) { WorkspaceManagerTestHelpers::StubConfig.new(root) }
	let(:context) { build_context(config: config, stdout: NonTTYStringIO.new, stderr: NonTTYStringIO.new) }

	before do
		context[:dry_run] = false
	end

	it 'removes worktrees and archives workspace artifacts' do
		session_id = 'slug--repo'
		worktree = File.join(config.worktrees_root, 'repo', 'slug')
		FileUtils.mkdir_p(worktree)
		File.write(File.join(worktree, '.keep'), '')

		manifest_file = File.join(config.workspaces_root, "#{session_id}.json")
		workspace_file = File.join(config.workspaces_root, "#{session_id}.code-workspace")
		session_dir = File.join(config.workspaces_root, session_id)

		File.write(manifest_file, JSON.pretty_generate({ 'repos' => [{ 'worktree' => worktree }] }) + "\n")
		File.write(workspace_file, '')
		FileUtils.mkdir_p(session_dir)

		log_messages = []
		WorkspaceManager::CLI::Output.stub(:log, ->(_ctx, level, message) { log_messages << [level, message] }) do
			WorkspaceManager::CLI::Commands::Prune.call(context, [session_id])
		end

		archive_dir = File.join(config.workspaces_root, 'archive')
		_(Dir.exist?(worktree)).must_equal(false)
		_(File.exist?(File.join(archive_dir, "#{session_id}.code-workspace"))).must_equal(true)
		_(File.exist?(File.join(archive_dir, "#{session_id}.json"))).must_equal(true)
		_(log_messages.any? { |level, _| level == :success }).must_equal(true)
	end

	it 'supports dry-run mode without deleting files' do
		context[:dry_run] = true
		session_id = 'slug--repo'
		manifest_file = File.join(config.workspaces_root, "#{session_id}.json")
		File.write(manifest_file, JSON.pretty_generate({ 'repos' => [] }) + "\n")

		error = nil
		begin
			WorkspaceManager::CLI::Commands::Prune.call(context, [session_id])
		rescue WorkspaceManager::Error => e
			error = e
		end

		_(error).must_be_nil
		_(File.exist?(manifest_file)).must_equal(true)
	end

	it 'removes feature branches recorded in the manifest' do
		session_id = 'slug--repo'
		repo_root = File.join(root, 'repo-source')
		FileUtils.mkdir_p(repo_root)

		system('git', 'init', '-b', 'main', repo_root)
		system('git', '-C', repo_root, 'config', 'user.email', 'tester@example.com')
		system('git', '-C', repo_root, 'config', 'user.name', 'Workspace Tester')
		File.write(File.join(repo_root, 'README.md'), "hello\n")
		system('git', '-C', repo_root, 'add', '.')
		system('git', '-C', repo_root, 'commit', '-m', 'initial commit')

		branch = 'feature/slug'
		system('git', '-C', repo_root, 'branch', branch)
		_(WorkspaceManager::CLI::Runtime.branch_exists?(context, repo_root, branch)).must_equal(true)

		worktree = File.join(config.worktrees_root, 'repo', 'slug')
		FileUtils.mkdir_p(worktree)

		manifest_file = File.join(config.workspaces_root, "#{session_id}.json")
		payload = {
			'repos' => [{
				'repo' => 'repo',
				'root' => repo_root,
				'worktree' => worktree,
				'branch' => branch,
				'base' => 'main'
			}]
		}
		File.write(manifest_file, JSON.pretty_generate(payload) + "\n")

		WorkspaceManager::CLI::Commands::Prune.call(context, [session_id])

		_(WorkspaceManager::CLI::Runtime.branch_exists?(context, repo_root, branch)).must_equal(false)
	end

	it 'raises when manifest is missing' do
		_(proc { WorkspaceManager::CLI::Commands::Prune.call(context, ['missing']) }).must_raise(WorkspaceManager::Error)
	end

	it 'parses options for prune command' do
		args = %w[--session slug --dry-run]
		options = WorkspaceManager::CLI::Commands::Prune.parse_options(context, args)
		_(options[:session_id]).must_equal('slug')
		_(context[:dry_run]).must_equal(true)
		_(args).must_equal([])
	end
end
