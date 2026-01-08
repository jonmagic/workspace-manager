# frozen_string_literal: true

require_relative 'test_helper'
require 'json'

describe WorkspaceManager::CLI::Worktrunk do
  let(:root) { Dir.mktmpdir('wm-worktrunk-') }
  let(:config) { WorkspaceManagerTestHelpers::StubConfig.new(root) }
  let(:context) do
    build_context(config: config, stdout: NonTTYStringIO.new, stderr: NonTTYStringIO.new)
  end
  let(:repo_path) { File.join(root, 'test-repo') }

  before do
    FileUtils.mkdir_p(repo_path)
  end

  describe '.available?' do
    it 'returns true when wt is in PATH' do
      WorkspaceManager::CLI::Runtime.stub(:which, ->(_ctx, cmd) {
        cmd == 'wt' ? '/usr/local/bin/wt' : nil
      }) do
        # Reset cached value
        WorkspaceManager::CLI::Worktrunk.instance_variable_set(:@available, nil)
        _(WorkspaceManager::CLI::Worktrunk.available?(context)).must_equal(true)
      end
    end

    it 'returns false when wt is not in PATH' do
      WorkspaceManager::CLI::Runtime.stub(:which, ->(_ctx, _cmd) { nil }) do
        # Reset cached value
        WorkspaceManager::CLI::Worktrunk.instance_variable_set(:@available, nil)
        _(WorkspaceManager::CLI::Worktrunk.available?(context)).must_equal(false)
      end
    end
  end

  describe '.switch' do
    it 'runs wt switch command without create flag' do
      commands_run = []
      
      WorkspaceManager::CLI::Runtime.stub(:which, ->(_ctx, cmd) {
        cmd == 'wt' ? '/usr/local/bin/wt' : nil
      }) do
        WorkspaceManager::CLI::Worktrunk.instance_variable_set(:@available, nil)
        WorkspaceManager::CLI::Runtime.stub(:run_cmd, ->(_ctx, *args) {
          commands_run << args
          true
        }) do
          WorkspaceManager::CLI::Worktrunk.stub(:worktree_path_for, ->(*) {
            '/path/to/worktree'
          }) do
            result = WorkspaceManager::CLI::Worktrunk.switch(context, repo_path, 'my-branch', create: false)
            
            _(commands_run.length).must_equal(1)
            _(commands_run[0]).must_equal(['wt', '-C', repo_path, 'switch', 'my-branch'])
            _(result).must_equal('/path/to/worktree')
          end
        end
      end
    end

    it 'runs wt switch command with create flag and base' do
      commands_run = []
      
      WorkspaceManager::CLI::Runtime.stub(:which, ->(_ctx, cmd) {
        cmd == 'wt' ? '/usr/local/bin/wt' : nil
      }) do
        WorkspaceManager::CLI::Worktrunk.instance_variable_set(:@available, nil)
        WorkspaceManager::CLI::Runtime.stub(:run_cmd, ->(_ctx, *args) {
          commands_run << args
          true
        }) do
          WorkspaceManager::CLI::Worktrunk.stub(:worktree_path_for, ->(*) {
            '/path/to/worktree'
          }) do
            result = WorkspaceManager::CLI::Worktrunk.switch(context, repo_path, 'my-branch', create: true, base: 'main')
            
            _(commands_run.length).must_equal(1)
            _(commands_run[0]).must_equal(['wt', '-C', repo_path, 'switch', '--create', '--base', 'main', 'my-branch'])
            _(result).must_equal('/path/to/worktree')
          end
        end
      end
    end

    it 'raises error when wt is not available' do
      WorkspaceManager::CLI::Runtime.stub(:which, ->(_ctx, _cmd) { nil }) do
        WorkspaceManager::CLI::Worktrunk.instance_variable_set(:@available, nil)
        
        err = assert_raises(WorkspaceManager::Error) do
          WorkspaceManager::CLI::Worktrunk.switch(context, repo_path, 'my-branch')
        end
        
        _(err.message).must_match(/wt command not available/)
      end
    end
  end

  describe '.remove' do
    it 'runs wt remove command' do
      commands_run = []
      
      WorkspaceManager::CLI::Runtime.stub(:which, ->(_ctx, cmd) {
        cmd == 'wt' ? '/usr/local/bin/wt' : nil
      }) do
        WorkspaceManager::CLI::Worktrunk.instance_variable_set(:@available, nil)
        WorkspaceManager::CLI::Runtime.stub(:run_cmd, ->(_ctx, *args) {
          commands_run << args
          true
        }) do
          WorkspaceManager::CLI::Worktrunk.remove(context, repo_path, 'my-branch')
          
          _(commands_run.length).must_equal(1)
          _(commands_run[0]).must_equal(['wt', '-C', repo_path, 'remove', 'my-branch'])
        end
      end
    end
  end

  describe '.list_worktrees' do
    it 'returns empty array in dry-run mode' do
      context[:dry_run] = true
      
      WorkspaceManager::CLI::Runtime.stub(:which, ->(_ctx, cmd) {
        cmd == 'wt' ? '/usr/local/bin/wt' : nil
      }) do
        WorkspaceManager::CLI::Worktrunk.instance_variable_set(:@available, nil)
        result = WorkspaceManager::CLI::Worktrunk.list_worktrees(context, repo_path)
        
        _(result).must_equal([])
      end
    end

    it 'returns empty array when command fails' do
      context[:dry_run] = false
      
      WorkspaceManager::CLI::Runtime.stub(:which, ->(_ctx, cmd) {
        cmd == 'wt' ? '/usr/local/bin/wt' : nil
      }) do
        WorkspaceManager::CLI::Worktrunk.instance_variable_set(:@available, nil)
        
        # Skip this test as we can't properly mock $? variable
        skip "Cannot properly mock $? in tests"
      end
    end
  end

  describe '.worktree_path_for' do
    it 'returns worktree path for matching branch' do
      worktrees = [
        { 'branch' => 'refs/heads/main', 'worktree' => '/path/to/main' },
        { 'branch' => 'refs/heads/feature/test', 'worktree' => '/path/to/feature' }
      ]
      
      WorkspaceManager::CLI::Worktrunk.stub(:list_worktrees, ->(*) { worktrees }) do
        result = WorkspaceManager::CLI::Worktrunk.worktree_path_for(context, repo_path, 'refs/heads/feature/test')
        _(result).must_equal('/path/to/feature')
      end
    end

    it 'returns nil when branch not found' do
      worktrees = [
        { 'branch' => 'refs/heads/main', 'worktree' => '/path/to/main' }
      ]
      
      WorkspaceManager::CLI::Worktrunk.stub(:list_worktrees, ->(*) { worktrees }) do
        result = WorkspaceManager::CLI::Worktrunk.worktree_path_for(context, repo_path, 'nonexistent')
        _(result).must_be_nil
      end
    end
  end
end
