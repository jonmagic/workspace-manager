# frozen_string_literal: true

require_relative '../test_helper'
require 'json'
require 'time'

describe WorkspaceManager::CLI::Commands::Rotate do
  let(:root) { Dir.mktmpdir('wm-rotate-') }
  let(:config) { WorkspaceManagerTestHelpers::StubConfig.new(root) }
  let(:repo_paths) do
    {
      'hamzo' => [File.join(root, 'repos', 'hamzo')],
      'flipper' => [File.join(root, 'repos', 'flipper')]
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
  end

  it 'rotates workspace to a new branch across all repos' do
    session_id = 'test-feature--hamzo+flipper'
    manifest_file = File.join(config.workspaces_root, "#{session_id}.json")
    workspace_file = File.join(config.workspaces_root, "#{session_id}.code-workspace")

    # Create initial manifest
    manifest = {
      'session_id' => session_id,
      'feature' => 'Test Feature',
      'slug' => 'test-feature',
      'created_at' => Time.now.utc.iso8601,
      'repos' => [
        {
          'repo' => 'hamzo',
          'root' => repo_paths['hamzo'].first,
          'worktree' => File.join(config.worktrees_root, 'hamzo', 'test-feature'),
          'branch' => 'feature/test-feature',
          'base' => 'main'
        },
        {
          'repo' => 'flipper',
          'root' => repo_paths['flipper'].first,
          'worktree' => File.join(config.worktrees_root, 'flipper', 'test-feature'),
          'branch' => 'feature/test-feature',
          'base' => 'main'
        }
      ]
    }

    workspace = {
      'folders' => [
        { 'path' => File.join(config.worktrees_root, 'hamzo', 'test-feature'), 'name' => 'hamzo' },
        { 'path' => File.join(config.worktrees_root, 'flipper', 'test-feature'), 'name' => 'flipper' }
      ],
      'settings' => {}
    }

    FileUtils.mkdir_p(config.workspaces_root)
    File.write(manifest_file, JSON.pretty_generate(manifest))
    File.write(workspace_file, JSON.pretty_generate(workspace))

    args = ['--session', session_id, '--branch', 'bugfix/issue-123', '--create', '--base', 'main']
    
    logs = []
    write_json_calls = []
    launch_calls = []
    git_commands = []

    WorkspaceManager::CLI::Runtime.stub(:ensure_directories, ->(*) { true }) do
      WorkspaceManager::CLI::Runtime.stub(:require_command, ->(*) { true }) do
        WorkspaceManager::CLI::Worktrunk.stub(:available?, ->(*) { false }) do
          WorkspaceManager::CLI::Runtime.stub(:branch_exists?, ->(*) { false }) do
            WorkspaceManager::CLI::Runtime.stub(:ensure_directory, ->(_ctx, path) { FileUtils.mkdir_p(path) }) do
              WorkspaceManager::CLI::Runtime.stub(:run_cmd, ->(_ctx, *args) {
                git_commands << args
                true
              }) do
                WorkspaceManager::CLI::Workspace.stub(:write_json, ->(_ctx, file, data) {
                  write_json_calls << [file, data]
                }) do
                  WorkspaceManager::CLI::Workspace.stub(:launch_editor, ->(_ctx, file) {
                    launch_calls << file
                  }) do
                    WorkspaceManager::CLI::Output.stub(:log, ->(_ctx, level, message) {
                      logs << [level, message]
                    }) do
                      WorkspaceManager::CLI::Commands::Rotate.call(context, args)
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    _(write_json_calls.length).must_equal(2)
    
    # Check workspace file was updated
    workspace_update = write_json_calls.find { |file, _| file == workspace_file }
    _(workspace_update).wont_be_nil
    updated_workspace = workspace_update[1]
    _(updated_workspace['folders'].length).must_equal(2)
    _(updated_workspace['folders'][0]['path']).must_equal(File.join(config.worktrees_root, 'hamzo', 'bugfix-issue-123'))
    _(updated_workspace['folders'][1]['path']).must_equal(File.join(config.worktrees_root, 'flipper', 'bugfix-issue-123'))

    # Check manifest was updated
    manifest_update = write_json_calls.find { |file, _| file == manifest_file }
    _(manifest_update).wont_be_nil
    updated_manifest = manifest_update[1]
    _(updated_manifest['current_branch']).must_equal('bugfix/issue-123')
    _(updated_manifest['repos'].length).must_equal(2)
    _(updated_manifest['repos'][0]['branch']).must_equal('bugfix/issue-123')
    _(updated_manifest['repos'][1]['branch']).must_equal('bugfix/issue-123')
    _(updated_manifest['rotation_history']).wont_be_nil
    _(updated_manifest['rotation_history'].length).must_equal(1)
    _(updated_manifest['rotation_history'][0]['branch']).must_equal('bugfix/issue-123')

    # Verify git commands were called
    _(git_commands.length).must_be(:>, 0)
  end

  it 'handles --dry-run flag correctly' do
    session_id = 'test-feature--hamzo'
    manifest_file = File.join(config.workspaces_root, "#{session_id}.json")
    workspace_file = File.join(config.workspaces_root, "#{session_id}.code-workspace")

    manifest = {
      'session_id' => session_id,
      'feature' => 'Test Feature',
      'slug' => 'test-feature',
      'created_at' => Time.now.utc.iso8601,
      'repos' => [
        {
          'repo' => 'hamzo',
          'root' => repo_paths['hamzo'].first,
          'worktree' => File.join(config.worktrees_root, 'hamzo', 'test-feature'),
          'branch' => 'feature/test-feature',
          'base' => 'main'
        }
      ]
    }

    workspace = {
      'folders' => [
        { 'path' => File.join(config.worktrees_root, 'hamzo', 'test-feature'), 'name' => 'hamzo' }
      ],
      'settings' => {}
    }

    FileUtils.mkdir_p(config.workspaces_root)
    File.write(manifest_file, JSON.pretty_generate(manifest))
    File.write(workspace_file, JSON.pretty_generate(workspace))

    context[:dry_run] = true
    args = ['--session', session_id, '--branch', 'new-branch']

    logs = []
    write_json_calls = []
    
    WorkspaceManager::CLI::Runtime.stub(:ensure_directories, ->(*) { true }) do
      WorkspaceManager::CLI::Runtime.stub(:require_command, ->(*) { true }) do
        WorkspaceManager::CLI::Worktrunk.stub(:available?, ->(*) { false }) do
          WorkspaceManager::CLI::Runtime.stub(:branch_exists?, ->(*) { false }) do
            WorkspaceManager::CLI::Runtime.stub(:ensure_directory, ->(_ctx, path) { FileUtils.mkdir_p(path) }) do
              WorkspaceManager::CLI::Runtime.stub(:run_cmd, ->(_ctx, *args) { true }) do
                WorkspaceManager::CLI::Workspace.stub(:write_json, ->(_ctx, file, data) {
                  write_json_calls << [file, data]
                }) do
                  WorkspaceManager::CLI::Workspace.stub(:launch_editor, ->(*) { true }) do
                    WorkspaceManager::CLI::Output.stub(:log, ->(_ctx, level, message) {
                      logs << [level, message]
                    }) do
                      err = assert_raises(WorkspaceManager::Error) do
                        WorkspaceManager::CLI::Commands::Rotate.call(context, args)
                      end
                      _(err.message).must_match(/Use --create to create it/)
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

  it 'raises error when manifest is not found' do
    args = ['--session', 'nonexistent-session', '--branch', 'test-branch']
    
    err = assert_raises(WorkspaceManager::Error) do
      WorkspaceManager::CLI::Commands::Rotate.call(context, args)
    end
    
    _(err.message).must_match(/Manifest not found/)
  end

  it 'raises error when branch is not provided' do
    args = ['--session', 'test-session']
    
    err = assert_raises(WorkspaceManager::Error) do
      WorkspaceManager::CLI::Commands::Rotate.call(context, args)
    end
    
    _(err.message).must_match(/target branch/)
  end
end
