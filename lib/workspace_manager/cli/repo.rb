# frozen_string_literal: true

require 'time'

module WorkspaceManager
  module CLI
    module Repo
      module_function

      def resolve(context, repos)
        repos.map do |token|
          path = select(context, token)
          Output.log(context, :info, "Resolved #{token} -> #{path}")
          [token, path]
        end.uniq { |name, _| name }
      end

      def select(context, token)
        candidates = context[:repo_locator].candidates(token)
        raise(Error, "Unable to locate clone for '#{token}'. Add it to your configured search patterns.") if candidates.empty?

        return candidates.first if candidates.length == 1

        prompt_select(context, "Multiple matches for '#{token}':", candidates)
      end

      def prepare_worktree(context, repo, repo_path, worktree_path, base_branch, branch_name)
        reuse_existing = context[:checkout_existing]
        chosen_branch = branch_name.dup

        branch_present = Runtime.branch_exists?(context, repo_path, branch_name)
        reuse_existing = false if reuse_existing && !branch_present

        if branch_present
          if reuse_existing
            Output.log(context, :info, "Reusing existing branch #{branch_name} for #{repo}")
          elsif Context.interactive?(context)
            reuse_existing = Runtime.prompt_yes_no(context, "Branch '#{branch_name}' already exists for #{repo}. Reuse it?", default: true)
            unless reuse_existing
              chosen_branch = "#{branch_name}-#{Time.now.to_i}"
              Output.log(context, :warn, "Using new branch name #{chosen_branch}")
            end
          else
            Output.log(context, :warn, "Branch '#{branch_name}' already exists; defaulting to reuse (--checkout-existing).")
            reuse_existing = true
          end
        end

        if reuse_existing
          Runtime.run_cmd(context, 'git', '-C', repo_path, 'worktree', 'add', worktree_path, chosen_branch)
        else
          Runtime.run_cmd(context, 'git', '-C', repo_path, 'fetch', '--all', '--prune')
          Runtime.run_cmd(context, 'git', '-C', repo_path, 'worktree', 'add', '-b', chosen_branch, worktree_path, base_branch)
        end

        chosen_branch
      end

      def prompt_select(context, prompt, options)
        raise(Error, 'User interaction is not possible in non-interactive mode') unless Context.interactive?(context)

        context[:stdout].puts prompt
        options.each_with_index do |option, index|
          context[:stdout].puts "  [#{index + 1}] #{option}"
        end

        loop do
          context[:stdout].print "Select option (1-#{options.length}) [1]: "
          input = context[:stdin].gets
          raise(Error, 'Selection cancelled') if input.nil?

          normalized = input.strip
          normalized = '1' if normalized.empty?
          if normalized.match?(/^[0-9]+$/)
            idx = normalized.to_i
            return options[idx - 1] if idx.positive? && idx <= options.length
          end

          context[:stdout].puts 'Invalid selection. Try again.'
        end
      end
    end
  end
end
