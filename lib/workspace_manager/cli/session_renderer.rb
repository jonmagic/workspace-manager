# frozen_string_literal: true

module WorkspaceManager
  module CLI
    module SessionRenderer
      module_function

      def render(context, sessions)
        label_width = 9
        divider = '─' * 64

        sessions.each_with_index do |session, index|
          block = session_block_lines(context, session, label_width)
          block.unshift(divider) if index.positive?
          Output.print_info_block(context, block)
        end
      end

      def session_block_lines(context, session, width)
        lines = []
        lines << format_row('Session', session['session_id'], width)
        lines << format_row('Status', session_status_label(context, session), width)
        lines << format_row('Created', session['timestamp'] || '—', width)
        lines << format_row('Workspace', session['workspace'] || '—', width)
        lines.concat(repo_rows(session['repos'], width))
        lines
      end

      def format_row(label, value, width)
        val = value
        val = '—' if val.nil? || (val.respond_to?(:empty?) && val.empty?)
        "#{label.ljust(width)} : #{val}"
      end

      def repo_rows(repos, width)
        return [format_row('Repos', '—', width)] if repos.empty?

        rows = []
        rows << "#{'Repos'.ljust(width)} :"
        repos.each do |repo|
          rows << indent_line("- #{repo['repo'] || 'unknown'}", 0)
          rows << indent_line("branch  : #{repo['branch'] || '—'}", 1)
          rows << indent_line("base    : #{repo['base'] || '—'}", 1)
          rows << indent_line("worktree: #{repo['worktree'] || '—'}", 1)
        end
        rows
      end

      def indent_line(text, level = 1)
        ('  ' * level) + text
      end

      def session_status_label(context, session)
        if session['status'] == 'active'
          Output.colorize(context, '🟢 active', :success)
        else
          Output.colorize(context, '⚪ stale', :warn)
        end
      end
    end
  end
end
