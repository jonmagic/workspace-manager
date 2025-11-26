# frozen_string_literal: true

require_relative '../test_helper'
require 'json'

describe WorkspaceManager::CLI::Commands::Remove do
  let(:root) { Dir.mktmpdir('wm-remove-') }
  let(:config) { WorkspaceManagerTestHelpers::StubConfig.new(root) }
  let(:context) { build_context(config: config, stdout: NonTTYStringIO.new, stderr: NonTTYStringIO.new) }

  before do
    context[:dry_run] = false
  end

  it 'removes worktrees, workspace artifacts, and session from history' do
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

    # Add to history
    history_file = File.join(root, 'history.json')
    context[:history_file] = history_file
    File.write(history_file, JSON.pretty_generate({ 'history' => [
      { 'session_id' => session_id, 'workspace' => workspace_file },
      { 'session_id' => 'other', 'workspace' => 'other.code-workspace' }
    ] }) + "\n")

    log_messages = []
    WorkspaceManager::CLI::Output.stub(:log, ->(_ctx, level, message) { log_messages << [level, message] }) do
      WorkspaceManager::CLI::Commands::Remove.call(context, [session_id])
    end

    _(Dir.exist?(worktree)).must_equal(false)
    _(File.exist?(manifest_file)).must_equal(false)
    _(File.exist?(workspace_file)).must_equal(false)
    _(Dir.exist?(session_dir)).must_equal(false)
    # Should be removed from history
    history = JSON.parse(File.read(history_file))
    history_list = history['history']
    _(history_list.any? { |entry| entry['session_id'] == session_id }).must_equal(false)
    _(history_list.any? { |entry| entry['session_id'] == 'other' }).must_equal(true)
    _(log_messages.any? { |level, _| level == :success }).must_equal(true)
  end

  it 'supports dry-run mode without deleting files' do
    context[:dry_run] = true
    session_id = 'slug--repo'
    manifest_file = File.join(config.workspaces_root, "#{session_id}.json")
    File.write(manifest_file, JSON.pretty_generate({ 'repos' => [] }) + "\n")
    history_file = File.join(root, 'history.json')
    context[:history_file] = history_file
    File.write(history_file, JSON.pretty_generate({ 'history' => [
      { 'session_id' => session_id, 'workspace' => manifest_file }
    ] }) + "\n")

    error = nil
    begin
      WorkspaceManager::CLI::Commands::Remove.call(context, [session_id])
    rescue WorkspaceManager::Error => e
      error = e
    end

    _(error).must_be_nil
    _(File.exist?(manifest_file)).must_equal(true)
    _(File.exist?(history_file)).must_equal(true)
  end

  it 'deletes feature branches referenced by the session when removing' do
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

    WorkspaceManager::CLI::Commands::Remove.call(context, [session_id])

    _(WorkspaceManager::CLI::Runtime.branch_exists?(context, repo_root, branch)).must_equal(false)
  end

  it 'raises when session cannot be found' do
    _(proc { WorkspaceManager::CLI::Commands::Remove.call(context, ['missing']) }).must_raise(WorkspaceManager::Error)
  end

  it 'removes archived session artifacts and history entries' do
    session_id = 'archived-session'
    archive_dir = File.join(config.workspaces_root, 'archive')
    FileUtils.mkdir_p(archive_dir)

    manifest_file = File.join(archive_dir, "#{session_id}.json")
    workspace_file = File.join(archive_dir, "#{session_id}.code-workspace")
    session_dir = File.join(archive_dir, session_id)
    FileUtils.mkdir_p(session_dir)

    File.write(manifest_file, JSON.pretty_generate({ 'repos' => [{ 'worktree' => '/tmp/does-not-exist' }] }))
    File.write(workspace_file, '')

    history_file = File.join(root, 'history.json')
    context[:history_file] = history_file
    File.write(history_file, JSON.pretty_generate({ 'history' => [
      { 'session_id' => session_id, 'workspace' => workspace_file }
    ] }) + "\n")

    WorkspaceManager::CLI::Commands::Remove.call(context, [session_id])

    _(File.exist?(manifest_file)).must_equal(false)
    _(File.exist?(workspace_file)).must_equal(false)
    _(Dir.exist?(session_dir)).must_equal(false)
    history = JSON.parse(File.read(history_file))
    _(history['history']).must_equal([])
  end

  it 'parses options for remove command' do
    args = %w[--session slug --dry-run]
    options = WorkspaceManager::CLI::Commands::Remove.parse_options(context, args)
    _(options[:session_id]).must_equal('slug')
    _(context[:dry_run]).must_equal(true)
    _(args).must_equal([])
  end
end
