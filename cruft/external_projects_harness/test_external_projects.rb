#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'open-uri'
require 'timeout'

# External projects test suite for gitlab_ci_cli
class ExternalProjectsTester
  PROJECTS = {
    'gitlab' => 'https://gitlab.com/gitlab-org/gitlab/-/raw/master/.gitlab-ci.yml',
    'fdroid' => 'https://gitlab.com/fdroid/fdroidserver/-/raw/master/.gitlab-ci.yml',
    'inkscape' => 'https://gitlab.com/inkscape/inkscape/-/raw/master/.gitlab-ci.yml',
    'gnome-builder' => 'https://gitlab.gnome.org/GNOME/gnome-builder/-/raw/main/.gitlab-ci.yml',
    'kicad' => 'https://gitlab.com/kicad/code/kicad/-/raw/master/.gitlab-ci.yml',
    'gstreamer' => 'https://gitlab.freedesktop.org/gstreamer/gstreamer/-/raw/main/.gitlab-ci.yml',
    'mesa' => 'https://gitlab.freedesktop.org/mesa/mesa/-/raw/main/.gitlab-ci.yml',
    'qemu' => 'https://gitlab.com/qemu-project/qemu/-/raw/master/.gitlab-ci.yml',
    'vlc' => 'https://gitlab.com/videolan/vlc/-/raw/master/.gitlab-ci.yml',
    'wireshark' => 'https://gitlab.com/wireshark/wireshark/-/raw/master/.gitlab-ci.yml'
  }.freeze

  COMMANDS = %w[lint dag dry-run].freeze
  TIMEOUT_SECONDS = 30

  def initialize(options = {})
    @base_dir = options[:base_dir] || 'external_projects_test'
    @cli_path = options[:cli_path] || './bin/gitlab_ci_cli'
    @verbose = options[:verbose] || false
    @results = {}
  end

  def run
    setup_directories
    download_projects
    test_all_projects
    generate_report
    cleanup if @cleanup

    # Return exit code based on results
    @results.values.all? { |r| r[:lint][:passed] } ? 0 : 1
  end

  private

  def setup_directories
    FileUtils.mkdir_p(@base_dir)
    PROJECTS.keys.each do |project|
      FileUtils.mkdir_p(File.join(@base_dir, project))
    end
  end

  def download_projects
    puts "Downloading GitLab CI files from #{PROJECTS.size} projects..."

    PROJECTS.each do |name, url|
      file_path = File.join(@base_dir, name, '.gitlab-ci.yml')

      begin
        content = URI.open(url).read
        File.write(file_path, content)
        puts "  ✓ #{name} (#{content.lines.count} lines)"
      rescue => e
        puts "  ✗ #{name}: #{e.message}"
        # Write empty file to mark as failed
        File.write(file_path + '.failed', e.message)
      end
    end
  end

  def test_all_projects
    puts "\nRunning tests on all projects..."

    PROJECTS.keys.each_with_index do |project, index|
      puts "\n[#{index + 1}/#{PROJECTS.size}] Testing #{project}..."

      @results[project] = {}
      ci_file = File.join(@base_dir, project, '.gitlab-ci.yml')

      # Skip if download failed
      if File.exist?(ci_file + '.failed')
        COMMANDS.each do |command|
          @results[project][command.to_sym] = { passed: false, error: 'Download failed' }
        end
        next
      end

      # Run each command
      COMMANDS.each do |command|
        result = run_command(project, command, ci_file)
        @results[project][command.to_sym] = result

        status = result[:passed] ? '✓' : '✗'
        puts "  #{command}: #{status}"
      end
    end
  end

  def run_command(project, command, ci_file)
    output_file = File.join(@base_dir, project, "#{command}.txt")

    cmd = "#{@cli_path} #{command} --entry #{ci_file}"

    begin
      output = nil
      exit_code = nil

      Timeout::timeout(TIMEOUT_SECONDS) do
        output = `#{cmd} 2>&1`
        exit_code = $?.exitstatus
      end

      File.write(output_file, output)

      {
        passed: exit_code == 0,
        exit_code: exit_code,
        output: output.lines.first(5).join
      }
    rescue Timeout::Error
      File.write(output_file, "Command timed out after #{TIMEOUT_SECONDS} seconds")
      {
        passed: false,
        error: 'Timeout',
        output: 'Timeout'
      }
    rescue => e
      {
        passed: false,
        error: e.message,
        output: e.message
      }
    end
  end

  def generate_report
    # Calculate statistics
    stats = { lint: 0, dag: 0, 'dry-run': 0 }

    @results.each do |_project, results|
      stats[:lint] += 1 if results[:lint][:passed]
      stats[:dag] += 1 if results[:dag][:passed]
      stats[:'dry-run'] += 1 if results[:'dry-run'][:passed]
    end

    # Generate JSON report
    report = {
      timestamp: Time.now.iso8601,
      projects_tested: PROJECTS.size,
      statistics: {
        lint: "#{stats[:lint]}/#{PROJECTS.size}",
        dag: "#{stats[:dag]}/#{PROJECTS.size}",
        'dry-run': "#{stats[:'dry-run']}/#{PROJECTS.size}"
      },
      results: @results
    }

    File.write(File.join(@base_dir, 'test_results.json'), JSON.pretty_generate(report))

    # Print summary
    puts "\n" + "=" * 50
    puts "Test Summary"
    puts "=" * 50

    puts "\nStatistics:"
    puts "  Lint:     #{stats[:lint]}/#{PROJECTS.size} passed (#{(stats[:lint] * 100.0 / PROJECTS.size).round}%)"
    puts "  DAG:      #{stats[:dag]}/#{PROJECTS.size} passed (#{(stats[:dag] * 100.0 / PROJECTS.size).round}%)"
    puts "  Dry-Run:  #{stats[:'dry-run']}/#{PROJECTS.size} passed (#{(stats[:'dry-run'] * 100.0 / PROJECTS.size).round}%)"

    # Print table
    puts "\n%-15s %-10s %-10s %-10s" % ["Project", "Lint", "DAG", "Dry-Run"]
    puts "-" * 45

    @results.each do |project, results|
      lint = results[:lint][:passed] ? '✓' : '✗'
      dag = results[:dag][:passed] ? '✓' : '✗'
      dryrun = results[:'dry-run'][:passed] ? '✓' : '✗'

      puts "%-15s %-10s %-10s %-10s" % [project, lint, dag, dryrun]
    end

    puts "\nDetailed results saved to: #{File.join(@base_dir, 'test_results.json')}"
  end

  def cleanup
    FileUtils.rm_rf(@base_dir) if Dir.exist?(@base_dir)
  end
end

# Run if executed directly
if __FILE__ == $0
  require 'optparse'

  options = {}

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on('-v', '--verbose', 'Verbose output') do
      options[:verbose] = true
    end

    opts.on('-c', '--cleanup', 'Clean up test files after run') do
      options[:cleanup] = true
    end

    opts.on('-d', '--dir DIR', 'Base directory for tests') do |dir|
      options[:base_dir] = dir
    end

    opts.on('-p', '--cli-path PATH', 'Path to gitlab_ci_cli') do |path|
      options[:cli_path] = path
    end
  end.parse!

  tester = ExternalProjectsTester.new(options)
  exit(tester.run)
end