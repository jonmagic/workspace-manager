# frozen_string_literal: true

require_relative 'test_helper'
require 'json'
require 'time'

describe WorkspaceManager::CLI::Context do
  it 'builds a context with defaults and injected repo locator' do
    context = build_context
    _(context[:argv]).must_equal([])
    _(context[:dry_run]).must_equal(true)
    _(context[:default_base]).must_equal('main')
    _(context[:repo_locator]).must_be_kind_of(WorkspaceManager::RepoLocator)
  end

  it 'detects interactive stdin based on tty?' do
    non_tty_context = build_context
    _(WorkspaceManager::CLI::Context.interactive?(non_tty_context)).must_equal(false)

    tty_context = build_context(stdin: TTYStringIO.new)
    _(WorkspaceManager::CLI::Context.interactive?(tty_context)).must_equal(true)
  end
end

describe WorkspaceManager::CLI::Helpers do
  it 'treats nil and empty values as blank' do
    _(WorkspaceManager::CLI::Helpers.blank?(nil)).must_equal(true)
    _(WorkspaceManager::CLI::Helpers.blank?('')).must_equal(true)
    _(WorkspaceManager::CLI::Helpers.blank?([])).must_equal(true)
    _(WorkspaceManager::CLI::Helpers.blank?('feature')).must_equal(false)
  end
end

describe WorkspaceManager::CLI::Output do
  let(:stdout) { TTYStringIO.new }
  let(:stderr) { TTYStringIO.new }
  let(:context) do
    build_context(stdout: stdout, stderr: stderr).merge(verbose: false, color_map: WorkspaceManager::CLI::COLOR_MAP)
  end

  it 'logs colored messages to stdout and suppresses debug output when not verbose' do
    WorkspaceManager::CLI::Output.log(context, :info, 'hello world')
    _(stdout.string).must_match(/\[INFO\]/)

    WorkspaceManager::CLI::Output.log(context, :debug, 'hidden')
    _(stdout.string).wont_match(/hidden/)
  end

  it 'writes debug output when verbose and sends errors to stderr' do
    context[:verbose] = true
    WorkspaceManager::CLI::Output.log(context, :debug, 'visible')
    _(stdout.string).must_match(/visible/)

    WorkspaceManager::CLI::Output.log(context, :error, 'broken')
    _(stderr.string).must_match(/\[ERROR\]/)
  end

  it 'colorizes text only when stdout is a tty' do
    colored = WorkspaceManager::CLI::Output.colorize(context, 'ok', :success)
    _(colored).must_match(/\e\[32m/)

    context[:stdout] = NonTTYStringIO.new
    plain = WorkspaceManager::CLI::Output.colorize(context, 'ok', :success)
    _(plain).must_equal('ok')
  end

  it 'prints blocks of information line by line' do
    WorkspaceManager::CLI::Output.print_info_block(context, ['line1', 'line2'])
    _(stdout.string).must_include("line1\nline2")
  end
end

describe WorkspaceManager::CLI::Runtime do
  let(:stdout) { NonTTYStringIO.new }
  let(:stderr) { NonTTYStringIO.new }
  let(:context) { build_context(stdout: stdout, stderr: stderr) }

  it 'ensures directories exist when not in dry-run mode' do
    context[:dry_run] = false
    WorkspaceManager::CLI::Runtime.ensure_directories(context)
    _(Dir.exist?(context[:worktrees_root])).must_equal(true)
    _(Dir.exist?(context[:workspaces_root])).must_equal(true)
  end

  it 'skips directory creation when dry-run is enabled' do
    Dir.mktmpdir('wm-runtime-dir-') do |dir|
      target = File.join(dir, 'new')
      WorkspaceManager::CLI::Runtime.ensure_directory(context, target)
      _(Dir.exist?(target)).must_equal(false)

      context[:dry_run] = false
      WorkspaceManager::CLI::Runtime.ensure_directory(context, target)
      _(Dir.exist?(target)).must_equal(true)
    end
  end

  it 'logs commands and returns immediately in dry-run mode' do
    context[:dry_run] = true
    _(WorkspaceManager::CLI::Runtime.run_cmd(context, 'echo', 'test')).must_equal(true)
  end

  it 'runs commands and raises on failure outside dry-run' do
    context[:dry_run] = false
    WorkspaceManager::CLI::Runtime.stub(:system, true) do
      _(WorkspaceManager::CLI::Runtime.run_cmd(context, 'true')).must_equal(true)
    end

    WorkspaceManager::CLI::Runtime.stub(:system, false) do
      _(proc { WorkspaceManager::CLI::Runtime.run_cmd(context, 'false') }).must_raise(WorkspaceManager::Error)
    end
  end

  it 'resolves executable paths and enforces required commands' do
    _(WorkspaceManager::CLI::Runtime.which(context, 'ruby')).wont_be_nil
    _(proc { WorkspaceManager::CLI::Runtime.require_command(context, 'definitely-missing-command') }).must_raise(WorkspaceManager::Error)
  end

  it 'prompts users for yes/no answers and respects defaults' do
    tty_stdin = TTYStringIO.new("\n")
    tty_stdout = TTYStringIO.new
    interactive_context = build_context(stdin: tty_stdin, stdout: tty_stdout)
    _(WorkspaceManager::CLI::Runtime.prompt_yes_no(interactive_context, 'Proceed?')).must_equal(true)

    tty_stdin.string = "n\n"
    tty_stdin.rewind
    _(WorkspaceManager::CLI::Runtime.prompt_yes_no(interactive_context, 'Again?', default: true)).must_equal(false)

    non_interactive = build_context
    _(proc { WorkspaceManager::CLI::Runtime.prompt_yes_no(non_interactive, 'Impossible') }).must_raise(WorkspaceManager::Error)
  end

  it 'checks branch existence using git' do
    Dir.mktmpdir('wm-runtime-git-') do |repo|
      system('git', 'init', repo, out: File::NULL, err: File::NULL)
      system('git', '-C', repo, 'config', 'user.email', 'ci@example.com')
      system('git', '-C', repo, 'config', 'user.name', 'CI')
      system('git', '-C', repo, 'commit', '--allow-empty', '-m', 'init', out: File::NULL, err: File::NULL)
      system('git', '-C', repo, 'branch', 'feature/test', out: File::NULL, err: File::NULL)

      _(WorkspaceManager::CLI::Runtime.branch_exists?(context, repo, 'feature/test')).must_equal(true)
      _(WorkspaceManager::CLI::Runtime.branch_exists?(context, repo, 'missing')).must_equal(false)
      _(WorkspaceManager::CLI::Runtime.branch_exists?(context, File.join(repo, 'nope'), 'main')).must_equal(false)
    end
  end
end

describe WorkspaceManager::CLI::Repo do
  let(:stdout) { TTYStringIO.new }
  let(:stdin) { TTYStringIO.new }
  let(:repo_locator) { WorkspaceManagerTestHelpers::StubRepoLocator.new('hamzo' => ['/repos/hamzo']) }
  let(:context) { build_context(stdout: stdout, stdin: stdin, repo_locator: repo_locator) }

  it 'resolves tokens via the repo locator and logs each mapping' do
    logs = []
    WorkspaceManager::CLI::Output.stub(:log, ->(ctx, level, message) { logs << [level, message] }) do
      result = WorkspaceManager::CLI::Repo.resolve(context, ['hamzo'])
      _(result).must_equal([['hamzo', '/repos/hamzo']])
    end
    _(logs.map(&:first)).must_include(:info)
  end

  it 'raises when a repo cannot be located' do
    missing_context = build_context(repo_locator: WorkspaceManagerTestHelpers::StubRepoLocator.new)
    _(proc { WorkspaceManager::CLI::Repo.select(missing_context, 'unknown') }).must_raise(WorkspaceManager::Error)
  end

  it 'prompts the user when multiple candidates exist' do
    stdin.string = "2\n"
    stdin.rewind
    multi_locator = WorkspaceManagerTestHelpers::StubRepoLocator.new('hamzo' => ['/a', '/b'])
    multi_context = build_context(stdin: stdin, stdout: stdout, repo_locator: multi_locator)
    _(WorkspaceManager::CLI::Repo.select(multi_context, 'hamzo')).must_equal('/b')
  end

  it 'reuses existing branches or creates new ones based on context flags' do
    context[:checkout_existing] = true
    run_calls = []

    WorkspaceManager::CLI::Runtime.stub(:branch_exists?, ->(_ctx, _repo, _branch) { true }) do
      WorkspaceManager::CLI::Runtime.stub(:run_cmd, ->(_ctx, *cmd) { run_calls << cmd; true }) do
        branch = nil
        WorkspaceManager::CLI::Runtime.stub(:prompt_yes_no, ->(*) { true }) do
          branch = WorkspaceManager::CLI::Repo.prepare_worktree(context, 'hamzo', '/repo', '/worktree', 'main', 'feature/slug')
        end
        _(branch).must_equal('feature/slug')
        _(run_calls.any? { |cmd| cmd.include?('worktree') }).must_equal(true)
      end
    end
  end

  it 'creates suffixed branch names when user declines reuse' do
    stdin.string = "n\n"
    stdin.rewind
    context[:checkout_existing] = false

    WorkspaceManager::CLI::Runtime.stub(:branch_exists?, ->(*_) { true }) do
      WorkspaceManager::CLI::Runtime.stub(:run_cmd, ->(*_) { true }) do
        WorkspaceManager::CLI::Runtime.stub(:prompt_yes_no, ->(*) { false }) do
          Time.stub(:now, Time.at(1700000000)) do
            new_branch = WorkspaceManager::CLI::Repo.prepare_worktree(context, 'hamzo', '/repo', '/worktree', 'main', 'feature/slug')
            _(new_branch).must_match(/feature\/slug-1700000000/)
          end
        end
      end
    end
  end

  it 'handles non-interactive reuse decisions by enabling checkout_existing' do
    non_interactive = build_context(repo_locator: repo_locator)
    non_interactive[:checkout_existing] = false
    WorkspaceManager::CLI::Runtime.stub(:branch_exists?, ->(*_) { true }) do
      WorkspaceManager::CLI::Runtime.stub(:run_cmd, ->(*_) { true }) do
        WorkspaceManager::CLI::Runtime.stub(:prompt_yes_no, ->(*) { true }) do
          _(WorkspaceManager::CLI::Repo.prepare_worktree(non_interactive, 'hamzo', '/repo', '/worktree', 'main', 'feature/slug')).must_equal('feature/slug')
        end
      end
    end
  end
end

describe WorkspaceManager::CLI::Workspace do
  let(:context) { build_context(stdout: NonTTYStringIO.new, stderr: NonTTYStringIO.new) }

  it 'slugifies feature names and validates presence' do
    _(WorkspaceManager::CLI::Workspace.slugify('Flipper Feature Improvements')).must_equal('flipper-feature-improvements')
    _(proc { WorkspaceManager::CLI::Workspace.slugify('???') }).must_raise(WorkspaceManager::Error)
  end

  it 'builds session ids deterministically' do
    _(WorkspaceManager::CLI::Workspace.build_session_id('slug', 'primary', %w[b a])).must_equal('slug--primary+a+b')
    _(WorkspaceManager::CLI::Workspace.build_session_id('slug', 'primary', [])).must_equal('slug--primary')
  end

  it 'resolves base branches with overrides' do
    context[:base_overrides]['foo'] = 'develop'
    _(WorkspaceManager::CLI::Workspace.base_for(context, 'foo')).must_equal('develop')
    _(WorkspaceManager::CLI::Workspace.base_for(context, 'bar')).must_equal(context[:default_base])
  end

  it 'writes workspace and manifest files with pretty json' do
    Dir.mktmpdir('wm-workspace-') do |dir|
      context[:dry_run] = false
      workspace_file = File.join(dir, 'session.code-workspace')
      manifest_file = File.join(dir, 'session.json')

      WorkspaceManager::CLI::Workspace.write_workspace_file(context, workspace_file, [{ path: '/worktree', name: 'hamzo' }])
      _(JSON.parse(File.read(workspace_file))['folders']).must_equal([{ 'path' => '/worktree', 'name' => 'hamzo' }])

      WorkspaceManager::CLI::Workspace.write_manifest_file(context, manifest_file, 'session', 'slug', [], [])
      data = JSON.parse(File.read(manifest_file))
      _(data['session_id']).must_equal('session')
      _(data['slug']).must_equal('slug')
    end
  end

  it 'logs dry-run writes without touching the filesystem' do
    Dir.mktmpdir('wm-workspace-dry-') do |dir|
      context[:dry_run] = true
      file = File.join(dir, 'workspace.code-workspace')
      logs = []
      WorkspaceManager::CLI::Output.stub(:log, ->(*args) { logs << args }) do
        WorkspaceManager::CLI::Workspace.write_json(context, file, { 'folders' => [] })
      end
      _(File.exist?(file)).must_equal(false)
      _(logs.flatten.join).must_include('dry-run')
    end
  end

  it 'prefills notes exactly once when text present' do
    Dir.mktmpdir('wm-notes-') do |dir|
      context[:dry_run] = false
      context[:notes_text] = 'Remember to ping QA.'
      WorkspaceManager::CLI::Workspace.prefill_notes(context, dir)
      notes_file = File.join(dir, 'notes.md')
      _(File.exist?(notes_file)).must_equal(true)
      WorkspaceManager::CLI::Workspace.prefill_notes(context, dir)
      _(File.read(notes_file)).must_include('Remember to ping QA.')
    end
  end

  it 'launches the editor when available and warns otherwise' do
    context[:dry_run] = false
    context[:no_open] = false
    WorkspaceManager::CLI::Runtime.stub(:which, ->(_ctx, cmd) { cmd == 'code' ? '/usr/local/bin/code' : nil }) do
      WorkspaceManager::CLI::Runtime.stub(:run_cmd, ->(*_) { true }) do
        _(WorkspaceManager::CLI::Workspace.launch_editor(context, '/tmp/workspace')).must_equal(true)
      end
    end

    WorkspaceManager::CLI::Runtime.stub(:which, ->(*_) { nil }) do
      logs = []
      WorkspaceManager::CLI::Output.stub(:log, ->(*args) { logs << args }) do
        WorkspaceManager::CLI::Workspace.launch_editor(context, '/tmp/workspace')
      end
      _(logs.flatten.join).must_include('skipping launch')
    end
  end
end

describe WorkspaceManager::CLI::History do
  let(:config_root) { Dir.mktmpdir('wm-history-') }
  let(:config) { WorkspaceManagerTestHelpers::StubConfig.new(config_root) }
  let(:context) { build_context(config: config, stdout: NonTTYStringIO.new, stderr: NonTTYStringIO.new) }

  before do
    context[:dry_run] = false
  end

  it 'appends entries to history, recreating corrupt files when necessary' do
    WorkspaceManager::CLI::History.append(context, 'session', '/tmp/workspace.code-workspace')
    data = JSON.parse(File.read(context[:history_file]))
    _(data['history'].length).must_equal(1)

    File.write(context[:history_file], 'not-json')
    WorkspaceManager::CLI::History.append(context, 'session-2', '/tmp/workspace2.code-workspace')
    data = JSON.parse(File.read(context[:history_file]))
    _(data['history'].last['session_id']).must_equal('session-2')
  end

  it 'reads history entries and tolerates malformed files' do
    WorkspaceManager::CLI::History.append(context, 'session', '/tmp/workspace.code-workspace')
    _(WorkspaceManager::CLI::History.read(context).first['session_id']).must_equal('session')

    File.write(context[:history_file], '{bad json')
    _(WorkspaceManager::CLI::History.read(context)).must_equal([])
  end

  it 'loads manifests, ignoring parse errors gracefully' do
    manifest_path = File.join(config.workspaces_root, 'session.json')
    File.write(manifest_path, JSON.pretty_generate({ 'slug' => 'slug' }) + "\n")
    _(WorkspaceManager::CLI::History.manifest_for(context, 'session')['slug']).must_equal('slug')

    File.write(manifest_path, '{oops')
    _(WorkspaceManager::CLI::History.manifest_for(context, 'session')).must_be_nil
  end

  it 'detects active sessions and builds snapshots' do
    manifest_path = File.join(config.workspaces_root, 'session.json')
    worktree_dir = File.join(config.worktrees_root, 'repo', 'slug')
    FileUtils.mkdir_p(worktree_dir)
    manifest = {
      'repos' => [{ 'repo' => 'repo', 'branch' => 'feature', 'base' => 'main', 'worktree' => worktree_dir }]
    }
    File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")
    entry = { 'session_id' => 'session', 'workspace' => File.join(config.workspaces_root, 'session.code-workspace'), 'timestamp' => Time.now.utc.iso8601 }
    File.write(entry['workspace'], '')

    manifest_data = WorkspaceManager::CLI::History.manifest_for(context, 'session')
    _(WorkspaceManager::CLI::History.session_active?(context, manifest_data, entry)).must_equal(true)

    snapshot = WorkspaceManager::CLI::History.session_snapshot(context, entry, manifest_data)
    _(snapshot['status']).must_equal('active')
    _(snapshot['repos'].first['repo']).must_equal('repo')
  end

  it 'resolves workspaces from identifiers and file paths' do
    session_id = 'slug--repo'
    workspace_file = File.join(config.workspaces_root, "#{session_id}.code-workspace")
    File.write(workspace_file, '')
    WorkspaceManager::CLI::History.append(context, session_id, workspace_file)

    workspace, entry, resolved_session = WorkspaceManager::CLI::History.resolve_workspace_from_token(context, session_id, WorkspaceManager::CLI::History.read(context))
    _(workspace).must_equal(workspace_file)
    _(entry['session_id']).must_equal(session_id)
    _(resolved_session).must_equal(session_id)

    workspace2, _entry2, resolved2 = WorkspaceManager::CLI::History.resolve_workspace_from_token(context, workspace_file, WorkspaceManager::CLI::History.read(context))
    _(workspace2).must_equal(workspace_file)
    _(resolved2).must_equal(session_id)

    nonexistent = File.join(config.workspaces_root, 'missing.code-workspace')
    _(proc { WorkspaceManager::CLI::History.resolve_workspace_from_token(context, nonexistent, []) }).must_raise(WorkspaceManager::Error)
  end

  it 'finds history entries by session or workspace path' do
    entries = [
      { 'session_id' => 'one', 'workspace' => '/tmp/one.code-workspace' },
      { 'session_id' => 'two', 'workspace' => '/tmp/two.code-workspace' }
    ]

    _(WorkspaceManager::CLI::History.find_history_entry_by_session(entries, 'two')['session_id']).must_equal('two')

    _(WorkspaceManager::CLI::History.find_history_entry_by_workspace(entries, '/tmp/one.code-workspace')['session_id']).must_equal('one')
  end
end

describe WorkspaceManager::CLI do
  let(:config) { WorkspaceManagerTestHelpers::StubConfig.new(Dir.mktmpdir('wm-cli-')) }
  let(:stdout) { NonTTYStringIO.new }
  let(:stderr) { NonTTYStringIO.new }

  it 'prints usage when no command is provided' do
    ctx = build_context(config: config, stdout: stdout, stderr: stderr, argv: [])
    WorkspaceManager::CLI.execute(ctx)
    _(stdout.string).must_include('Usage: wm')
  end

  it 'prints version information for the version command' do
    ctx = build_context(config: config, stdout: stdout, stderr: stderr, argv: ['version'])
    WorkspaceManager::CLI.execute(ctx)
    _(stdout.string).must_match(/workspace-manager/)
  end

  it 'invokes the init command when requested' do
    ctx = build_context(config: config, stdout: stdout, stderr: stderr, argv: ['init'])
    called = []
    WorkspaceManager::CLI::Commands::Init.stub(:call, ->(context, args) { called << [context, args] }) do
      WorkspaceManager::CLI.execute(ctx)
    end
    _(called.length).must_equal(1)
  end

  it 'raises friendly errors for unknown commands during execute' do
    ctx = build_context(config: config, stdout: stdout, stderr: stderr, argv: ['mystery'])
    _(proc { WorkspaceManager::CLI.execute(ctx) }).must_raise(WorkspaceManager::Error)
  end

  it 'logs errors and exits with code 1 when run encounters an error' do
    log_messages = []
    WorkspaceManager::CLI::Output.stub(:log, ->(_ctx, level, message) { log_messages << [level, message] }) do
      begin
        WorkspaceManager::CLI.stub(:exit, ->(code) { raise RuntimeError, code.to_s }) do
          WorkspaceManager::CLI.run(['bogus'], config: config, stdin: NonTTYStringIO.new, stdout: stdout, stderr: stderr)
        end
      rescue RuntimeError => e
        _(e.message).must_equal('1')
      end
    end
    _(log_messages.flatten.join).must_include('Unknown command')
  end
end

describe WorkspaceManager::CLI::SessionRenderer do
  let(:context) { build_context(stdout: TTYStringIO.new, stderr: NonTTYStringIO.new) }

  it 'formats session details and delegates to Output' do
    sessions = [{
      'session_id' => 'slug--hamzo',
      'status' => 'active',
      'timestamp' => '2023-01-01T00:00:00Z',
      'workspace' => '/workspace',
      'repos' => [{ 'repo' => 'hamzo', 'branch' => 'feature/slug', 'base' => 'main', 'worktree' => '/worktree' }]
    }]

    lines = nil
    WorkspaceManager::CLI::Output.stub(:print_info_block, ->(_ctx, block) { lines = block }) do
      WorkspaceManager::CLI::SessionRenderer.render(context, sessions)
    end

    _(lines.join("\n")).must_include('Session')
    _(WorkspaceManager::CLI::SessionRenderer.session_status_label(context, { 'status' => 'active' })).must_match(/🟢/)
    _(WorkspaceManager::CLI::SessionRenderer.session_status_label(context, { 'status' => 'stale' })).must_match(/⚪/)
  end

  it 'formats repo rows with indentation' do
    rows = WorkspaceManager::CLI::SessionRenderer.repo_rows([], 5)
    _(rows.first).must_match(/Repos/)

    rows = WorkspaceManager::CLI::SessionRenderer.repo_rows([{ 'repo' => 'hamzo', 'branch' => 'feature', 'base' => 'main', 'worktree' => '/tree' }], 5)
    _(rows.join("\n")).must_include('branch  : feature')
  end
end
