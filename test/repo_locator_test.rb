require_relative 'test_helper'
require 'fileutils'

describe WorkspaceManager::RepoLocator do
  let(:env) { {} }
  let(:config) { WorkspaceManager::Config.new(env: env) }
  let(:locator) { WorkspaceManager::RepoLocator.new(config) }
  let(:config_file) do
    dir = Dir.mktmpdir('wm-locator-config-')
    path = File.join(dir, 'config.json')
    File.write(path, "{}\n")
    path
  end

  before do
    env['WORKSPACE_MANAGER_CONFIG_FILE'] = config_file
  end

  it 'returns an empty list for blank tokens' do
    _(locator.candidates('   ')).must_equal([])
  end

  it 'finds direct matches and globbed directories under each root' do
    Dir.mktmpdir('wm-locator-') do |root|
      direct = File.join(root, 'hamzo')
      nested_parent = File.join(root, 'clients', 'ops')
      nested = File.join(nested_parent, 'hamzo')
      [direct, nested].each { |path| FileUtils.mkdir_p(path) }

      # Instead of '**', explicitly add possible parent directories
      env['WORKSPACE_MANAGER_SEARCH_PATTERNS'] = [root, nested_parent].join(',')

      _(locator.candidates('hamzo')).must_include(direct)
      _(locator.candidates('hamzo')).must_include(nested)
    end
  end

  it 'supports placeholder patterns when building glob expressions' do
    Dir.mktmpdir('wm-locator-placeholder-') do |root|
      mirror = File.join(root, 'mirrors', 'spamurai-next')
      FileUtils.mkdir_p(mirror)

      env['WORKSPACE_MANAGER_SEARCH_PATTERNS'] = File.join(root, 'mirrors', '%{repo}')

      _(locator.candidates('spamurai-next')).must_equal([mirror])
    end
  end

  it 'expands globbed root patterns and filters duplicate matches' do
    Dir.mktmpdir('wm-locator-glob-') do |root|
      parent = File.join(root, 'code')
      team = File.join(parent, 'team-alpha')
      repo_path = File.join(team, 'hamzo')
      FileUtils.mkdir_p(repo_path)

      env['WORKSPACE_MANAGER_SEARCH_PATTERNS'] = File.join(parent, '*')

      results = locator.candidates('hamzo')
      _(results).must_include(repo_path)
      _(results.uniq.size).must_equal(results.size)
    end
  end

  it 'ignores directories inside worktree folders' do
    Dir.mktmpdir('wm-locator-worktrees-') do |root|
      repo_path = File.join(root, 'worktrees', 'hamzo', 'hamzo')
      FileUtils.mkdir_p(repo_path)

      # Instead of '**', explicitly add possible parent directories
      env['WORKSPACE_MANAGER_SEARCH_PATTERNS'] = [File.join(root, 'worktrees', 'hamzo')].join(',')

      _(locator.candidates('hamzo')).wont_include(repo_path)
    end
  end
  it 'honors explicit search patterns and supports repo placeholders' do
    Dir.mktmpdir('wm-locator-patterns-') do |root|
      owners = %w[foo bar]
      owners.each do |owner|
        FileUtils.mkdir_p(File.join(root, owner, 'hamzo'))
      end

      env['WORKSPACE_MANAGER_SEARCH_PATTERNS'] = File.join(root, '*')

      matches = locator.candidates('hamzo')
      _(matches.length).must_equal(owners.length)
      owners.each do |owner|
        _(matches).must_include(File.join(root, owner, 'hamzo'))
      end
    end
  end

  it 'expands patterns containing %{repo}' do
    Dir.mktmpdir('wm-locator-pattern-placeholder-') do |root|
      mirror = File.join(root, 'mirrors', 'hamzo')
      FileUtils.mkdir_p(mirror)

      env['WORKSPACE_MANAGER_SEARCH_PATTERNS'] = File.join(root, 'mirrors', '%{repo}')

      _(locator.candidates('hamzo')).must_equal([mirror])
    end
  end

  it 'treats literal directories without placeholders as direct matches' do
    Dir.mktmpdir('wm-locator-literal-') do |root|
      brain = File.join(root, 'brain')
      FileUtils.mkdir_p(brain)

      env['WORKSPACE_MANAGER_SEARCH_PATTERNS'] = brain

      _(locator.candidates('brain')).must_equal([brain])
    end
  end
end
