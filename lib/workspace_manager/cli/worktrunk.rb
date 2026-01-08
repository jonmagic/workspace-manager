# frozen_string_literal: true

require 'json'
require 'open3'

module WorkspaceManager
  module CLI
    module Worktrunk
      module_function

      # Check if wt (Worktrunk) is available
      def available?(context)
        return @available unless @available.nil?

        @available = !Runtime.which(context, 'wt').nil?
      end

      # Switch to a branch worktree, creating if needed
      # Returns the worktree path
      def switch(context, repo_path, branch, create: false, base: nil)
        raise(Error, 'wt command not available') unless available?(context)

        args = ['wt', '-C', repo_path, 'switch']
        args << '--create' if create
        args << '--base' << base if create && base
        args << branch

        Runtime.run_cmd(context, *args)
        
        # Get the worktree path for this branch
        worktree_path_for(context, repo_path, branch)
      end

      # Remove a branch worktree using wt
      def remove(context, repo_path, branch)
        raise(Error, 'wt command not available') unless available?(context)

        Runtime.run_cmd(context, 'wt', '-C', repo_path, 'remove', branch)
      end

      # List worktrees and return parsed JSON
      def list_worktrees(context, repo_path)
        raise(Error, 'wt command not available') unless available?(context)

        return [] if context[:dry_run]

        require 'open3'
        output, status = Open3.capture2('wt', '-C', repo_path, 'list', '--format=json', err: File::NULL)
        return [] unless status.success?

        JSON.parse(output)
      rescue JSON::ParserError
        []
      end

      # Get worktree path for a specific branch
      def worktree_path_for(context, repo_path, branch)
        worktrees = list_worktrees(context, repo_path)
        entry = worktrees.find { |w| w['branch'] == branch || w['branch'] == "refs/heads/#{branch}" }
        entry ? entry['worktree'] : nil
      end
    end
  end
end
