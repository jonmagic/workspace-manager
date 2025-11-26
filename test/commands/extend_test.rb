# frozen_string_literal: true

require_relative '../test_helper'
require 'json'
require 'time'

describe WorkspaceManager::CLI::Commands::Extend do
  let(:root) { Dir.mktmpdir('wm-extend-') }
  let(:config) { WorkspaceManagerTestHelpers::StubConfig.new(root) }
  let(:repo_paths) do
    {
      'hamzo' => [File.join(root, 'repos', 'hamzo')],
      'spamurai-next' => [File.join(root, 'repos', 'spamurai-next')],
      'brain' => [File.join(root, 'folders', 'brain')]
    }
  end
  let(:repo_locator) { WorkspaceManagerTestHelpers::StubRepoLocator.new(repo_paths) }
  let(:context) do
    build_context(config: config, repo_locator: repo_locator, stdout: NonTTYStringIO.new, stderr: NonTTYStringIO.new)
  end

  before do
    repo_paths.values.flatten.each { |path| FileUtils.mkdir_p(path) }
    context[:dry_run] = false
    context[:no_open] = true
    context[:extra_folders] = []
  end

  it 'extends a session manifest and workspace with new repo entries' do
    session_id = 'flipper-feature-improvements--hamzo'
    slug = 'flipper-feature-improvements'
    manifest_file = File.join(config.workspaces_root, "#{session_id}.json")
    workspace_file = File.join(config.workspaces_root, "#{session_id}.code-workspace")

    existing_worktree = File.join(config.worktrees_root, 'hamzo', slug)
    FileUtils.mkdir_p(existing_worktree)

    existing_manifest_entry = {
      'repo' => 'hamzo',
      'root' => repo_paths['hamzo'].first,
      'worktree' => existing_worktree,
      'branch' => "feature/#{slug}",
      'base' => 'main'
    }

    File.write(manifest_file, JSON.pretty_generate({
      'session_id' => session_id,
      'feature' => 'Flipper Feature Improvements',
      'slug' => slug,
      'created_at' => Time.now.utc.iso8601,
      'repos' => [existing_manifest_entry]
    }) + "\n")

    File.write(workspace_file, JSON.pretty_generate({
      'folders' => [
        { 'path' => existing_worktree, 'name' => 'hamzo' }
      ],
      'settings' => {}
    }) + "\n")

    prepared = []
    WorkspaceManager::CLI::Repo.stub(:prepare_worktree, ->(_ctx, repo, repo_path, worktree_path, base_branch, branch_name) {
      prepared << [repo, repo_path, worktree_path, base_branch, branch_name]
      branch_name
    }) do
      WorkspaceManager::CLI::Commands::Extend.call(context, [session_id, 'spamurai-next'])
    end

    _(prepared.length).must_equal(1)
    _, repo_path, worktree_path, base_branch, branch_name = prepared.first
    _(repo_path).must_equal(repo_paths['spamurai-next'].first)
    _(worktree_path).must_equal(File.join(config.worktrees_root, 'spamurai-next', slug))
    _(base_branch).must_equal('main')
    _(branch_name).must_equal("feature/#{slug}")

    manifest = JSON.parse(File.read(manifest_file))
    _(manifest['repos'].map { |entry| entry['repo'] }).must_include('spamurai-next')
    _(manifest).must_include('updated_at')

    workspace = JSON.parse(File.read(workspace_file))
    paths = workspace['folders'].map { |folder| folder['path'] }
    _(paths).must_include(File.join(config.worktrees_root, 'spamurai-next', slug))
  end

  it 'extends a session with folder-only additions without requiring git' do
    session_id = 'brainstorm--hamzo'
    slug = 'brainstorm'
    manifest_file = File.join(config.workspaces_root, "#{session_id}.json")
    workspace_file = File.join(config.workspaces_root, "#{session_id}.code-workspace")

    File.write(manifest_file, JSON.pretty_generate({
      'session_id' => session_id,
      'feature' => 'Brainstorm',
      'slug' => slug,
      'created_at' => Time.now.utc.iso8601,
      'repos' => []
    }) + "\n")

    File.write(workspace_file, JSON.pretty_generate({
      'folders' => [],
      'settings' => {}
    }) + "\n")

    folder_path = File.join(root, 'brain')
    FileUtils.mkdir_p(folder_path)

    context[:extra_folders] = [{ path: File.expand_path(folder_path), name: 'brain' }]

    require_called = false
    WorkspaceManager::CLI::Runtime.stub(:require_command, ->(*) { require_called = true }) do
      WorkspaceManager::CLI::Workspace.stub(:launch_editor, ->(*) { true }) do
        WorkspaceManager::CLI::Commands::Extend.call(context, [session_id])
      end
    end

    _(require_called).must_equal(false)

    manifest = JSON.parse(File.read(manifest_file))
    _(manifest['folders'].map { |entry| entry['path'] }).must_include(File.expand_path(folder_path))

    workspace = JSON.parse(File.read(workspace_file))
    _(workspace['folders'].map { |entry| entry['path'] }).must_include(File.expand_path(folder_path))
  end

  it 'rejects adding repositories that already exist in manifest' do
    session_id = 'flipper-feature-improvements--hamzo'
    slug = 'flipper-feature-improvements'
    manifest_file = File.join(config.workspaces_root, "#{session_id}.json")
    workspace_file = File.join(config.workspaces_root, "#{session_id}.code-workspace")

    File.write(manifest_file, JSON.pretty_generate({
      'session_id' => session_id,
      'feature' => 'Flipper Feature Improvements',
      'slug' => slug,
      'created_at' => Time.now.utc.iso8601,
      'repos' => [{
        'repo' => 'hamzo',
        'root' => repo_paths['hamzo'].first,
        'worktree' => File.join(config.worktrees_root, 'hamzo', slug),
        'branch' => "feature/#{slug}",
        'base' => 'main'
      }]
    }) + "\n")

    File.write(workspace_file, JSON.pretty_generate({
      'folders' => [
        { 'path' => File.join(config.worktrees_root, 'hamzo', slug), 'name' => 'hamzo' }
      ]
    }) + "\n")

    error = _(proc { WorkspaceManager::CLI::Commands::Extend.call(context, [session_id, 'hamzo']) }).must_raise(WorkspaceManager::Error)
    _(error.message).must_match(/already part of session/i)
  end

  it 'parses command-line options including base overrides and flags' do
    folder_path = repo_paths['brain'].first
    args = %w[--session test --base develop --base repo:release --folder brain --checkout-existing --dry-run --no-open --verbose]
    argv = args.dup
    options = WorkspaceManager::CLI::Commands::Extend.parse_options(context, argv)
    _(options[:session]).must_equal('test')
    _(context[:default_base]).must_equal('develop')
    _(context[:base_overrides]['repo']).must_equal('release')
    _(context[:checkout_existing]).must_equal(true)
    _(context[:dry_run]).must_equal(true)
    _(context[:no_open]).must_equal(true)
    _(context[:verbose]).must_equal(true)
    extra = context[:extra_folders]
    _(extra.length).must_equal(1)
    _(extra.first[:path]).must_equal(File.expand_path(folder_path))
    _(extra.first[:name]).must_equal('brain')
    context[:extra_folders].clear
    _(argv).must_equal([])
  end

  it 'raises descriptive errors when manifest or workspace files are missing' do
    _(proc { WorkspaceManager::CLI::Commands::Extend.call(context, ['missing-session', 'hamzo']) }).must_raise(WorkspaceManager::Error)
  end
end
