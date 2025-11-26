# frozen_string_literal: true

require_relative '../test_helper'
require 'json'

describe WorkspaceManager::CLI::Commands::Config do
  let(:stdout) { NonTTYStringIO.new }
  let(:stderr) { NonTTYStringIO.new }

  it 'pretty prints the current configuration JSON' do
    Dir.mktmpdir('wm-config-test-') do |temp_dir|
      config_path = File.join(temp_dir, 'config.json')
      data = {
        'worktrees_root' => File.join(temp_dir, 'worktrees'),
        'workspaces_root' => File.join(temp_dir, 'workspaces'),
        'history_file' => File.join(temp_dir, 'history.json'),
        'repo_config' => File.join(temp_dir, 'repos.json'),
        'search' => {
          'patterns' => [File.join(temp_dir, 'projects', '*')]
        }
      }

      File.write(config_path, JSON.pretty_generate(data))

      env = {
        'WORKSPACE_MANAGER_CONFIG_FILE' => config_path
      }

      config = WorkspaceManager::Config.new(env: env)
      context = build_context(argv: [], config: config, stdout: stdout, stderr: stderr)

      WorkspaceManager::CLI::Commands::Config.call(context, [])

      output = stdout.string
      _(JSON.parse(output)).must_equal(data)
    end
  end

  it 'supports --help flag' do
    context = build_context(stdout: stdout, stderr: stderr)

    err = _(-> { WorkspaceManager::CLI::Commands::Config.call(context, ['--help']) }).must_raise(SystemExit)
    _(err.status).must_equal(0)
    _(stdout.string).must_include('Usage: wm config')
  end
end
