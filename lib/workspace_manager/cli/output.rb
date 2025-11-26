# frozen_string_literal: true

module WorkspaceManager
  module CLI
    module Output
      module_function

      def log(context, level, message)
        return if level == :debug && !context[:verbose]

        stream = level == :error ? context[:stderr] : context[:stdout]
        color_code = context[:color_map][level]
        if color_code && stream.tty?
          color = "\e[#{color_code}m"
          reset = "\e[0m"
        else
          color = ''
          reset = ''
        end

        stream.puts("#{color}[#{level.to_s.upcase}]#{reset} #{message}")
      end

      def colorize(context, text, level_key)
        code = context[:color_map][level_key]
        stream = context[:stdout]
        return text unless code && stream.tty?

        "\e[#{code}m#{text}\e[0m"
      end

      def print_info_block(context, lines)
        lines.each { |line| context[:stdout].puts(line) }
      end
    end
  end
end
