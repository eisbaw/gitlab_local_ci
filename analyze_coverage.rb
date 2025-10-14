#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

# Determine project root directory (where this script is located)
PROJECT_ROOT = File.expand_path(__dir__)

# Load the coverage results
resultset = JSON.parse(File.read('coverage/.resultset.json'))
coverage_data = resultset['RSpec']['coverage']

# Calculate per-file statistics
file_stats = []

coverage_data.each do |file_path, file_data|
  # Skip files outside lib/ or inside gitlab submodule
  next unless file_path.start_with?(File.join(PROJECT_ROOT, 'lib/'))
  next if file_path.include?('/gitlab/')

  # lines is an array where index = line number (1-indexed), value = hit count
  # nil means not relevant for coverage, integer means relevant (0 = not covered, >0 = covered)
  lines_array = file_data['lines']

  total_relevant = 0
  covered = 0
  uncovered_lines = []

  lines_array.each_with_index do |hit_count, index|
    line_num = index + 1  # Lines are 1-indexed

    # Skip irrelevant lines (nil values - comments, blank lines, etc.)
    next if hit_count.nil?

    # This is a relevant executable line
    total_relevant += 1

    if hit_count == 0
      # Line not covered
      uncovered_lines << line_num
    else
      # Line covered (hit_count > 0)
      covered += 1
    end
  end

  next if total_relevant == 0

  percentage = (covered.to_f / total_relevant * 100).round(2)
  short_path = file_path.sub(PROJECT_ROOT + '/', '')

  file_stats << {
    path: short_path,
    total: total_relevant,
    covered: covered,
    percentage: percentage,
    uncovered: uncovered_lines
  }
end

# Sort by coverage percentage (lowest first)
file_stats.sort_by! { |s| s[:percentage] }

# Print overall summary
total_lines = file_stats.sum { |s| s[:total] }
total_covered = file_stats.sum { |s| s[:covered] }
overall_percentage = total_lines > 0 ? (total_covered.to_f / total_lines * 100).round(2) : 0.0

puts "=" * 80
puts "COVERAGE REPORT SUMMARY"
puts "=" * 80
puts
puts "Overall Line Coverage: #{overall_percentage}% (#{total_covered} / #{total_lines} lines)"
puts "Coverage Threshold: 90%"
puts "Status: #{overall_percentage >= 90 ? 'PASS' : 'FAIL - Below threshold'}"
puts

# Files below threshold
below_threshold = file_stats.select { |s| s[:percentage] < 90.0 }

if below_threshold.empty?
  puts "All files meet or exceed 90% coverage threshold!"
  puts
else
  puts "FILES BELOW 90% COVERAGE:"
  puts "-" * 80
  below_threshold.each do |stat|
    printf "%-60s %6.2f%% (%d / %d)\n",
           stat[:path],
           stat[:percentage],
           stat[:covered],
           stat[:total]

    if stat[:uncovered].length <= 20
      puts "  Uncovered lines: #{stat[:uncovered].join(', ')}"
    else
      puts "  Uncovered lines: #{stat[:uncovered][0..19].join(', ')}... (#{stat[:uncovered].length - 20} more)"
    end
    puts
  end
end

# Files at or above threshold
at_threshold = file_stats.select { |s| s[:percentage] >= 90.0 }

unless at_threshold.empty?
  puts "FILES AT OR ABOVE 90% COVERAGE:"
  puts "-" * 80
  at_threshold.each do |stat|
    printf "%-60s %6.2f%% (%d / %d)\n",
           stat[:path],
           stat[:percentage],
           stat[:covered],
           stat[:total]
  end
  puts
end

# Recommendations
if overall_percentage < 90.0
  puts "=" * 80
  puts "RECOMMENDATIONS TO REACH 90% COVERAGE:"
  puts "=" * 80
  puts

  lines_needed = ((total_lines * 0.90) - total_covered).ceil
  puts "Need to cover #{lines_needed} more lines to reach 90% overall coverage."
  puts
  puts "Priority files to focus on (sorted by coverage %):"
  below_threshold[0..4].each do |stat|
    lines_to_add = ((stat[:total] * 0.90) - stat[:covered]).ceil
    printf "  • %-50s needs %3d more lines covered\n", stat[:path], lines_to_add
  end
end
