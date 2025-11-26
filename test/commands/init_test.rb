# frozen_string_literal: true

require_relative '../test_helper'
require 'json'
require 'time'

describe WorkspaceManager::CLI::Commands::Init do
  let(:root) { Dir.mktmpdir('wm-init-') }
  let(:config) { WorkspaceManagerTestHelpers::StubConfig.new(root) }
  let(:repo_paths) do
    {
      'hamzo' => [File.join(root, 'repos', 'hamzo')],
      'flipper' => [File.join(root, 'repos', 'flipper')],
      'brain' => [File.join(root, 'folders', 'brain')]
    }
  end
  let(:repo_locator) { WorkspaceManagerTestHelpers::StubRepoLocator.new(repo_paths) }
  let(:context) do
    build_context(config: config, repo_locator: repo_locator, stdout: NonTTYStringIO.new, stderr: NonTTYStringIO.new)
  end

  before do
    repo_paths.each_value { |paths| paths.each { |path| FileUtils.mkdir_p(path) } }
    context[:dry_run] = false
    context[:no_open] = true
    context[:extra_folders].clear if context[:extra_folders]
  end

  it 'parses options, resolves repositories, and produces workspace artifacts' do
    args = ['--feature', 'Flipper Feature Improvements', '--primary', 'hamzo', '--base', 'develop', '--notes', 'Kickoff', '--checkout-existing', '--verbose', 'hamzo', 'flipper']

    workspace_records = []
    manifest_records = []
    history_records = []
    logs = []
    prepared = []

    workspace_file = File.join(config.workspaces_root, 'flipper-feature-improvements--hamzo+flipper.code-workspace')
    manifest_file = File.join(config.workspaces_root, 'flipper-feature-improvements--hamzo+flipper.json')

    # Make flipper worktree pre-populated to exercise reuse warning path
    flipper_worktree = File.join(config.worktrees_root, 'flipper', 'flipper-feature-improvements')
    FileUtils.mkdir_p(flipper_worktree)
    File.write(File.join(flipper_worktree, '.keep'), '')

    WorkspaceManager::CLI::Runtime.stub(:ensure_directories, ->(*) { true }) do
      WorkspaceManager::CLI::Runtime.stub(:require_command, ->(*) { true }) do
        WorkspaceManager::CLI::Runtime.stub(:ensure_directory, ->(_ctx, path) { FileUtils.mkdir_p(path) }) do
          WorkspaceManager::CLI::Repo.stub(:prepare_worktree, ->(_ctx, repo, repo_path, worktree_path, base_branch, branch_name) {
            prepared << [repo, repo_path, worktree_path, base_branch, branch_name]
            branch_name
          }) do
            WorkspaceManager::CLI::Workspace.stub(:write_workspace_file, ->(_ctx, file, folders) { workspace_records << [file, folders] }) do
              WorkspaceManager::CLI::Workspace.stub(:write_manifest_file, ->(_ctx, file, session_id, slug, repos, folders) {
                manifest_records << [file, session_id, slug, repos, folders]
              }) do
                WorkspaceManager::CLI::History.stub(:append, ->(_ctx, session_id, file) { history_records << [session_id, file] }) do
                  WorkspaceManager::CLI::Workspace.stub(:prefill_notes, ->(*) { true }) do
                    WorkspaceManager::CLI::Workspace.stub(:launch_editor, ->(*) { true }) do
                      WorkspaceManager::CLI::Output.stub(:log, ->(_ctx, level, message) { logs << [level, message] }) do
                        WorkspaceManager::CLI::Commands::Init.call(context, args)
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    _(context[:feature_name]).must_equal('Flipper Feature Improvements')
    _(context[:default_base]).must_equal('develop')
    _(context[:checkout_existing]).must_equal(true)
    _(prepared.length).must_equal(1)
    repo, repo_path, worktree_path, base_branch, branch_name = prepared.first
    _(repo).must_equal('hamzo')
    _(repo_path).must_equal(repo_paths['hamzo'].first)
    _(worktree_path).must_equal(File.join(config.worktrees_root, 'hamzo', 'flipper-feature-improvements'))
    _(base_branch).must_equal('develop')
    _(branch_name).must_equal('feature/flipper-feature-improvements')

    file, folders = workspace_records.first
    _(file).must_equal(workspace_file)
    _(folders.any? { |folder| folder[:repo] == 'flipper' }).must_equal(true)

    manifest_entry = manifest_records.first
    _(manifest_entry[0]).must_equal(manifest_file)
    _(manifest_entry[2]).must_equal('flipper-feature-improvements')
    _(manifest_entry[3].first['repo']).must_equal('hamzo')
    _(manifest_entry[4]).must_equal([])

    _(history_records.first).must_equal(['flipper-feature-improvements--hamzo+flipper', workspace_file])
    _(logs.flatten.join).must_match(/Workspace ready/)
    _(logs.any? { |level, message| level == :warn && message.include?('Worktree path already exists') }).must_equal(true)
  end

  it 'raises informative errors for missing features or repos' do
    _(proc { WorkspaceManager::CLI::Commands::Init.call(context, ['hamzo']) }).must_raise(WorkspaceManager::Error)
    _(proc { WorkspaceManager::CLI::Commands::Init.call(context, ['--feature', 'Story']) }).must_raise(WorkspaceManager::Error)
  end

  it 'parses command-line options for init' do
    folder_path = repo_paths['brain'].first
    args = %w[--feature Story --primary flipper --base main --base repo:develop --notes hi --folder brain --checkout-existing --dry-run --no-open --verbose repo1]
    WorkspaceManager::CLI::Commands::Init.parse_options(context, args)
    _(context[:feature_name]).must_equal('Story')
    _(context[:primary_repo]).must_equal('flipper')
    _(context[:default_base]).must_equal('main')
    _(context[:base_overrides]['repo']).must_equal('develop')
    _(context[:notes_text]).must_equal('hi')
    _(context[:checkout_existing]).must_equal(true)
    _(context[:dry_run]).must_equal(true)
    _(context[:no_open]).must_equal(true)
    _(context[:verbose]).must_equal(true)
    extra = context[:extra_folders]
    _(extra.length).must_equal(1)
    _(extra.first[:path]).must_equal(File.expand_path(folder_path))
    _(extra.first[:name]).must_equal('brain')
    _(args).must_equal(['repo1'])
  end

  it 'resolves folder tokens through repo locator when not explicit paths' do
    context[:extra_folders].clear
    WorkspaceManager::CLI::Commands::Init.parse_options(context, ['--feature', 'Story', '--folder', 'brain', 'repo1'])

    extra = context[:extra_folders]
    _(extra.length).must_equal(1)
    _(extra.first[:path]).must_equal(File.expand_path(repo_paths['brain'].first))
    _(extra.first[:name]).must_equal('brain')
  end

  it 'adds additional folders to workspace manifest when requested' do
    args = ['--feature', 'Brainstorm', 'hamzo']
    folder_path = File.join(root, 'brain')
    FileUtils.mkdir_p(folder_path)

    context[:extra_folders] = [{ path: folder_path, name: 'brain' }]

    workspace_records = []
    manifest_records = []

    WorkspaceManager::CLI::Runtime.stub(:ensure_directories, ->(*) { true }) do
      WorkspaceManager::CLI::Runtime.stub(:require_command, ->(*) { true }) do
        WorkspaceManager::CLI::Runtime.stub(:ensure_directory, ->(_ctx, path) { FileUtils.mkdir_p(path) }) do
          WorkspaceManager::CLI::Repo.stub(:prepare_worktree, ->(*) { 'feature/brainstorm' }) do
            WorkspaceManager::CLI::Workspace.stub(:write_workspace_file, ->(_ctx, _file, folders) { workspace_records << folders }) do
              WorkspaceManager::CLI::Workspace.stub(:write_manifest_file, ->(_ctx, _file, _session_id, _slug, repos, folders) {
                manifest_records << [repos, folders]
              }) do
                WorkspaceManager::CLI::History.stub(:append, ->(*) { true }) do
                  WorkspaceManager::CLI::Workspace.stub(:prefill_notes, ->(*) { true }) do
                    WorkspaceManager::CLI::Workspace.stub(:launch_editor, ->(*) { true }) do
                      WorkspaceManager::CLI::Commands::Init.call(context, args)
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    workspace_entry_paths = workspace_records.first.map { |folder| folder[:path] }
    _(workspace_entry_paths).must_include(folder_path)

    repos_entries, folder_entries = manifest_records.first
    _(repos_entries.length).must_equal(1)
    _(folder_entries.length).must_equal(1)
    _(folder_entries.first['path']).must_equal(folder_path)
    _(folder_entries.first['name']).must_equal('brain')
  end
end
