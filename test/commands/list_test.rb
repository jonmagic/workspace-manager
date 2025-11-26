# frozen_string_literal: true

require_relative '../test_helper'
require 'json'

describe WorkspaceManager::CLI::Commands::List do
  let(:context) { build_context(stdout: NonTTYStringIO.new, stderr: NonTTYStringIO.new) }

  it 'logs info when history is empty' do
    logs = []
    WorkspaceManager::CLI::History.stub(:read, []) do
      WorkspaceManager::CLI::Output.stub(:log, ->(_ctx, level, message) { logs << [level, message] }) do
        WorkspaceManager::CLI::Commands::List.call(context, [])
      end
    end
    _(logs.first).must_equal([:info, 'No workspace sessions found.'])
  end

  it 'filters, limits, and renders sessions using SessionRenderer' do
    sessions = [
      { 'session_id' => 'one', 'timestamp' => '2023-01-02', 'workspace' => '/w1' },
      { 'session_id' => 'two', 'timestamp' => '2023-01-01', 'workspace' => '/w2' }
    ]

    manifest = { 'repos' => [] }
    rendered = []

    WorkspaceManager::CLI::History.stub(:read, sessions) do
      WorkspaceManager::CLI::History.stub(:manifest_for, manifest) do
        WorkspaceManager::CLI::History.stub(:session_snapshot, ->(_ctx, entry, _manifest) {
          { 'session_id' => entry['session_id'], 'timestamp' => entry['timestamp'], 'workspace' => entry['workspace'], 'status' => entry['session_id'] == 'one' ? 'active' : 'stale', 'repos' => [] }
        }) do
          WorkspaceManager::CLI::SessionRenderer.stub(:render, ->(_ctx, list) { rendered.concat(list) }) do
            WorkspaceManager::CLI::Commands::List.call(context, ['--limit', '1', '--active'])
          end
        end
      end
    end

    _(rendered.length).must_equal(1)
    _(rendered.first['session_id']).must_equal('one')
  end

  it 'outputs JSON when requested and handles reverse ordering' do
    sessions = [
      { 'session_id' => 'one', 'timestamp' => '2023-01-01', 'workspace' => '/w1' }
    ]

    WorkspaceManager::CLI::History.stub(:read, sessions) do
      WorkspaceManager::CLI::History.stub(:manifest_for, {}) do
        WorkspaceManager::CLI::History.stub(:session_snapshot, ->(_ctx, entry, _manifest) {
          { 'session_id' => entry['session_id'], 'timestamp' => entry['timestamp'], 'workspace' => entry['workspace'], 'status' => 'stale', 'repos' => [] }
        }) do
          WorkspaceManager::CLI::Output.stub(:log, ->(*) { raise 'should not log for json' }) do
            context[:stdout] = NonTTYStringIO.new
            WorkspaceManager::CLI::Commands::List.call(context, ['--json', '--reverse'])
            json = JSON.parse(context[:stdout].string)
            _(json.first['session_id']).must_equal('one')
          end
        end
      end
    end
  end

  it 'notifies when filters remove all sessions' do
    sessions = [{ 'session_id' => 'one', 'timestamp' => '2023-01-01', 'workspace' => '/w1' }]
    logs = []

    WorkspaceManager::CLI::History.stub(:read, sessions) do
      WorkspaceManager::CLI::History.stub(:manifest_for, {}) do
        WorkspaceManager::CLI::History.stub(:session_snapshot, ->(_ctx, entry, _manifest) {
          { 'session_id' => entry['session_id'], 'timestamp' => entry['timestamp'], 'workspace' => entry['workspace'], 'status' => 'stale', 'repos' => [] }
        }) do
          WorkspaceManager::CLI::Output.stub(:log, ->(_ctx, level, message) { logs << [level, message] }) do
            WorkspaceManager::CLI::Commands::List.call(context, ['--active'])
          end
        end
      end
    end

    _(logs.last).must_equal([:info, 'No workspace sessions matched the filters.'])
  end

  it 'parses command-line options for list command' do
    args = %w[--limit 5 --active --json --reverse]
    options = WorkspaceManager::CLI::Commands::List.parse_options(context, args)
    _(options[:limit]).must_equal(5)
    _(options[:active_only]).must_equal(true)
    _(options[:json]).must_equal(true)
    _(options[:reverse]).must_equal(true)
    _(args).must_equal([])
  end
end
