# frozen_string_literal: true

require 'coverage'

begin
  Coverage.start(lines: true)
rescue ArgumentError
  Coverage.start
end

PROJECT_ROOT = File.expand_path('..', __dir__)
LIB_ROOT = File.join(PROJECT_ROOT, 'lib')

at_exit do
  result = nil
  begin
    result = Coverage.result
  rescue StandardError => e
    warn "Coverage could not be collected: #{e.message}"
    next
  end

  total_lines = 0
  covered_lines = 0
  summaries = []

  Array(result).each do |path, data|
    next unless path.start_with?(LIB_ROOT)

    line_counts =
      if data.is_a?(Hash) && data.key?(:lines)
        data[:lines]
      else
        data
      end

    next unless line_counts.respond_to?(:each)

    file_total = 0
    file_covered = 0

    line_counts.each do |count|
      next if count.nil?
      file_total += 1
      file_covered += 1 if count&.positive?
    end

    next if file_total.zero?

    total_lines += file_total
    covered_lines += file_covered

    summaries << [path.sub("#{PROJECT_ROOT}/", ''), file_covered * 100.0 / file_total]
  end

  if total_lines.zero?
    $stdout.puts 'Coverage (lib/): 0.00% (0/0 lines)'
  else
    overall = covered_lines * 100.0 / total_lines
    $stdout.puts format('Coverage (lib/): %.2f%% (%d/%d lines)', overall, covered_lines, total_lines)

    summaries.sort_by! { |entry| entry.first }
    summaries.each do |file, pct|
      $stdout.puts format('  %s: %.2f%%', file, pct)
    end
  end
end
