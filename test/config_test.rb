require_relative 'test_helper'
require 'json'

describe WorkspaceManager::Config do
  def write_config_file(data = {})
    dir = Dir.mktmpdir('wm-config-')
    path = File.join(dir, 'config.json')
    File.write(path, JSON.pretty_generate(data))
    path
  end

  let(:env) do
    {
      'WORKSPACE_MANAGER_WORKTREES_ROOT' => '~/alpha',
      'WORKSPACE_MANAGER_WORKSPACES_ROOT' => '~/beta',
      'WORKSPACE_MANAGER_HISTORY_FILE' => '~/gamma/history.json',
      'WORKSPACE_MANAGER_REPO_CONFIG' => '~/delta/repos.json',
      'WORKSPACE_MANAGER_CONFIG_FILE' => write_config_file
    }
  end
  let(:config_path) { nil }
  let(:config) { WorkspaceManager::Config.new(env: env, config_path: config_path) }

  it 'raises an error if prohibited glob pattern is used' do
    env['WORKSPACE_MANAGER_SEARCH_PATTERNS'] = '/foo/**/*,/bar/*'
    _ { config.search_patterns }.must_raise WorkspaceManager::Config::ProhibitedGlob
  end

  let(:env) do
    {
      'WORKSPACE_MANAGER_WORKTREES_ROOT' => '~/alpha',
      'WORKSPACE_MANAGER_WORKSPACES_ROOT' => '~/beta',
      'WORKSPACE_MANAGER_HISTORY_FILE' => '~/gamma/history.json',
      'WORKSPACE_MANAGER_REPO_CONFIG' => '~/delta/repos.json',
      'WORKSPACE_MANAGER_CONFIG_FILE' => write_config_file
    }
  end
  let(:config_path) { nil }
  let(:config) { WorkspaceManager::Config.new(env: env, config_path: config_path) }

  describe '#search_patterns' do
    it 'returns an empty array when unset' do
      _(config.search_patterns).must_equal([])
    end

    it 'reads comma and semicolon separated values from env' do
      env['WORKSPACE_MANAGER_SEARCH_PATTERNS'] = '~/code,~/code/*;~/code/*/*'
      _(config.search_patterns).must_equal(['~/code', '~/code/*', '~/code/*/*'])
    end

    it 'reads list values from json config when not set in env' do
      env['WORKSPACE_MANAGER_CONFIG_FILE'] = write_config_file('search' => { 'patterns' => ['~/work', '~/code/*'] })
      _(config.search_patterns).must_equal(['~/work', '~/code/*'])
    end

    it 'deduplicates values while preserving order, but raises for prohibited globs' do
      env['WORKSPACE_MANAGER_SEARCH_PATTERNS'] = '~/code, ~/code, ~/code/**'
      _ { config.search_patterns }.must_raise WorkspaceManager::Config::ProhibitedGlob
    end
  end

  describe 'path helpers' do
    it 'exposes environment-backed directories' do
      env.merge!(
        'WORKSPACE_MANAGER_WORKTREES_ROOT' => '~/alpha',
        'WORKSPACE_MANAGER_WORKSPACES_ROOT' => '~/beta',
        'WORKSPACE_MANAGER_HISTORY_FILE' => '~/gamma/history.json',
        'WORKSPACE_MANAGER_REPO_CONFIG' => '~/delta/repos.json'
      )

      _(config.worktrees_root).must_equal(File.expand_path('~/alpha'))
      _(config.workspaces_root).must_equal(File.expand_path('~/beta'))
      _(config.history_file).must_equal(File.expand_path('~/gamma/history.json'))
      _(config.repo_config).must_equal(File.expand_path('~/delta/repos.json'))
    end
  end

  describe '#dry_run? and #verbose?' do
    it 'treats common truthy values as true' do
      %w[1 true YES On].each do |value|
        env['WORKSPACE_MANAGER_DRY_RUN'] = value
        _(config.dry_run?).must_equal(true)
      end

      env.delete('WORKSPACE_MANAGER_DRY_RUN')
      _(config.dry_run?).must_equal(false)
    end

    it 'returns false when environment flag absent' do
      _(config.verbose?).must_equal(false)
      env['WORKSPACE_MANAGER_VERBOSE'] = 'yes'
      _(config.verbose?).must_equal(true)
    end
  end

  describe 'configuration file handling' do
    it 'raises when JSON cannot be parsed' do
      Dir.mktmpdir('wm-config-invalid-') do |dir|
        json = File.join(dir, 'config.json')
        File.write(json, '{invalid json')
        env['WORKSPACE_MANAGER_CONFIG_FILE'] = json

        _ { config.search_patterns }.must_raise(WorkspaceManager::Config::LoadError)
      end
    end

    it 'raises when JSON top-level structure is not a mapping' do
      env['WORKSPACE_MANAGER_CONFIG_FILE'] = write_config_file(['invalid'])

      _ { config.search_patterns }.must_raise(WorkspaceManager::Config::LoadError)
    end

    it 'raises when config file is missing' do
      env['WORKSPACE_MANAGER_CONFIG_FILE'] = File.join(Dir.mktmpdir('wm-config-missing-'), 'nope.json')

      _ { config.search_patterns }.must_raise(WorkspaceManager::Config::MissingConfig)
    end
  end
end
