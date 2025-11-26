# frozen_string_literal: true

require_relative '../test_helper'

describe WorkspaceManager::CLI::Commands::Open do
  let(:context) { build_context(stdout: NonTTYStringIO.new, stderr: NonTTYStringIO.new) }

  it 'opens the most recent session and launches the editor' do
    Dir.mktmpdir('wm-open-') do |dir|
      workspace_file = File.join(dir, 'slug--repo.code-workspace')
      File.write(workspace_file, '')

      history = [
        { 'session_id' => 'slug--repo', 'workspace' => workspace_file, 'timestamp' => '2023-01-01T00:00:00Z' }
      ]

      snapshot = { 'session_id' => 'slug--repo', 'timestamp' => '2023', 'workspace' => workspace_file, 'status' => 'active', 'repos' => [] }

      WorkspaceManager::CLI::History.stub(:read, history) do
        WorkspaceManager::CLI::History.stub(:manifest_for, {}) do
          WorkspaceManager::CLI::History.stub(:session_snapshot, snapshot) do
            WorkspaceManager::CLI::SessionRenderer.stub(:session_block_lines, ['line']) do
              WorkspaceManager::CLI::Output.stub(:print_info_block, ->(_ctx, _) { true }) do
                launched = []
                context[:workspaces_root] = dir
                WorkspaceManager::CLI::Workspace.stub(:launch_editor, ->(_ctx, file) { launched << file }) do
                  WorkspaceManager::CLI::Commands::Open.call(context, ['--recent', '1'])
                end
                _(launched).must_equal([workspace_file])
              end
            end
          end
        end
      end
    end
  end

  it 'prints the workspace path when requested without launching editor' do
    Dir.mktmpdir('wm-open-print-') do |dir|
      workspace_file = File.join(dir, 'slug--repo.code-workspace')
      File.write(workspace_file, '')
      history = [{ 'session_id' => 'slug--repo', 'workspace' => workspace_file, 'timestamp' => '2023-01-01T00:00:00Z' }]

      WorkspaceManager::CLI::History.stub(:read, history) do
        WorkspaceManager::CLI::History.stub(:resolve_workspace_from_token, [workspace_file, history.first, 'slug--repo']) do
          WorkspaceManager::CLI::History.stub(:manifest_for, {}) do
            WorkspaceManager::CLI::History.stub(:session_snapshot, ->(*_) { { 'session_id' => 'slug--repo', 'timestamp' => '2023', 'workspace' => workspace_file, 'status' => 'stale', 'repos' => [] } }) do
              WorkspaceManager::CLI::SessionRenderer.stub(:session_block_lines, ['line']) do
                WorkspaceManager::CLI::Output.stub(:print_info_block, ->(*_) { true }) do
                  launches = []
                  WorkspaceManager::CLI::Workspace.stub(:launch_editor, ->(*_) { launches << :called }) do
                    context[:stdout] = NonTTYStringIO.new
                    WorkspaceManager::CLI::Commands::Open.call(context, ['--session', 'slug--repo', '--print'])
                    _(context[:stdout].string.strip).must_equal(workspace_file)
                    _(launches).must_equal([])
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  it 'raises friendly errors for invalid combinations' do
    _(proc { WorkspaceManager::CLI::Commands::Open.call(context, ['--recent', '0']) }).must_raise(WorkspaceManager::Error)
    _(proc { WorkspaceManager::CLI::Commands::Open.call(context, []) }).must_raise(WorkspaceManager::Error)
  end

  it 'parses command-line flags for open command' do
    args = %w[--session slug --recent 1 --print --no-open]
    options = WorkspaceManager::CLI::Commands::Open.parse_options(context, args)
    _(options[:session]).must_equal('slug')
    _(options[:recent]).must_equal(1)
    _(options[:print]).must_equal(true)
    _(context[:no_open]).must_equal(true)
    _(args).must_equal([])
  end
end
