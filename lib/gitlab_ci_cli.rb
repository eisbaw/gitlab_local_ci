# frozen_string_literal: true

require_relative 'version'

# Main module for GitLab CI CLI tool
module GitlabCiCli
  # CLI argument parsing and command routing
  # Follows MPED principles:
  # - No hidden state or globals
  # - Composable functions
  # - Fail-fast with clear error messages
  # - Data design before algorithm
  class CLI
    # Exit codes
    EXIT_SUCCESS = 0
    EXIT_INVALID_ARGS = 1
    EXIT_COMMAND_FAILED = 2

    # Valid values for flags
    VALID_PIPELINE_TYPES = %w[push merge_request schedule manual].freeze
    VALID_UNDEFINED_MODES = %w[warning error empty].freeze
    VALID_FORMATS = %w[text json junit].freeze
    VALID_COMMANDS = %w[lint dag dry-run help].freeze

    # Default values
    DEFAULTS = {
      entry: './.gitlab-ci.yml',
      project: Dir.pwd,
      runners: './runners',
      ref: 'HEAD',
      pipeline: 'push',
      undefined: 'warning',
      format: 'text',
      gitlab_dir: './gitlab',
      verbose: false,
      variables: {},
    }.freeze

    def self.start(args)
      # Parse arguments into options hash and command
      options, command = parse_args(args)

      # Validate arguments based on command requirements (fail-fast)
      validate_options(options, command)

      # Route to command handler
      exit_code = execute_command(command, options)
      exit(exit_code)
    rescue ArgumentError => e
      $stderr.puts "Error: #{e.message}"
      exit(EXIT_INVALID_ARGS)
    rescue StandardError => e
      $stderr.puts "Error: #{e.message}"
      $stderr.puts e.backtrace.join("\n") if options && options[:verbose]
      exit(EXIT_COMMAND_FAILED)
    end

    # Parse command-line arguments into options hash and command
    # Returns: [options_hash, command_string]
    # Raises: ArgumentError for invalid input
    def self.parse_args(args)
      options = DEFAULTS.dup
      options[:variables] = {} # Ensure mutable hash for variables
      command = nil
      i = 0

      while i < args.length
        arg = args[i]

        case arg
        when '--help', '-h'
          return [options, 'help']
        when '--version', '-v'
          print_version
          exit(EXIT_SUCCESS)
        when '--entry'
          options[:entry] = require_value(arg, args[i + 1])
          i += 1
        when '--project'
          options[:project] = require_value(arg, args[i + 1])
          i += 1
        when '--runners'
          options[:runners] = require_value(arg, args[i + 1])
          i += 1
        when '--ref'
          options[:ref] = require_value(arg, args[i + 1])
          i += 1
        when '--pipeline'
          value = require_value(arg, args[i + 1])
          validate_enum(arg, value, VALID_PIPELINE_TYPES)
          options[:pipeline] = value
          i += 1
        when '--variables', '--env'
          value = require_value(arg, args[i + 1])
          key, val = parse_key_value(arg, value)
          options[:variables][key] = val
          i += 1
        when '--undefined'
          value = require_value(arg, args[i + 1])
          validate_enum(arg, value, VALID_UNDEFINED_MODES)
          options[:undefined] = value
          i += 1
        when '--verbose'
          options[:verbose] = true
        when '--format'
          value = require_value(arg, args[i + 1])
          validate_enum(arg, value, VALID_FORMATS)
          options[:format] = value
          i += 1
        when '--gitlab-dir'
          options[:gitlab_dir] = require_value(arg, args[i + 1])
          i += 1
        else
          if arg.start_with?('--')
            raise ArgumentError, "Unknown flag: #{arg}"
          elsif command.nil?
            command = arg
          else
            raise ArgumentError, "Multiple commands specified: #{command}, #{arg}"
          end
        end

        i += 1
      end

      # Default to help if no command specified
      command ||= 'help'

      # Validate command
      unless VALID_COMMANDS.include?(command)
        raise ArgumentError, "Unknown command: #{command}. Valid commands: #{VALID_COMMANDS.join(', ')}"
      end

      [options, command]
    end

    # Require that a flag has a value
    # Raises: ArgumentError if value is missing
    def self.require_value(flag, value)
      if value.nil? || value.start_with?('--')
        raise ArgumentError, "Flag #{flag} requires a value"
      end
      value
    end

    # Validate that a value is in allowed set
    # Raises: ArgumentError if value is invalid
    def self.validate_enum(flag, value, allowed)
      unless allowed.include?(value)
        raise ArgumentError, "Invalid value '#{value}' for #{flag}. Must be one of: #{allowed.join(', ')}"
      end
    end

    # Parse KEY=VALUE format
    # Raises: ArgumentError if format is invalid
    def self.parse_key_value(flag, value)
      parts = value.split('=', 2)
      if parts.length != 2 || parts[0].empty?
        raise ArgumentError, "Flag #{flag} requires KEY=VALUE format, got: #{value}"
      end
      parts
    end

    # Validate options based on command requirements (fail-fast)
    # Raises: ArgumentError if validation fails
    def self.validate_options(options, command)
      # Help command needs no validation
      return if command == 'help'

      # Commands that need the entry file
      if %w[lint dag dry-run].include?(command)
        entry = options[:entry]
        unless File.exist?(entry)
          raise ArgumentError, "Entry file not found: #{entry}"
        end
      end

      # Commands that need the project directory
      if %w[dry-run].include?(command)
        project = options[:project]
        unless Dir.exist?(project)
          raise ArgumentError, "Project directory not found: #{project}"
        end
      end

      # Commands that need the runners directory
      if %w[dry-run].include?(command)
        runners = options[:runners]
        unless Dir.exist?(runners)
          raise ArgumentError, "Runners directory not found: #{runners}"
        end
      end
    end

    # Execute the specified command with options
    # Returns: exit code (0 for success, non-zero for failure)
    def self.execute_command(command, options)
      case command
      when 'help'
        print_help
        EXIT_SUCCESS
      when 'lint'
        execute_lint(options)
      when 'dag'
        execute_dag(options)
      when 'dry-run'
        execute_dry_run(options)
      else
        # Should never reach here due to validation, but fail-fast anyway
        $stderr.puts "BUG: Unhandled command: #{command}"
        EXIT_COMMAND_FAILED
      end
    end

    # Print version information
    def self.print_version
      puts "gitlab_ci_cli version #{VERSION}"
    end

    # Print help message
    def self.print_help
      puts <<~HELP
        gitlab_ci_cli - Local GitLab CI Pipeline Simulator

        USAGE:
            gitlab_ci_cli [OPTIONS] [COMMAND]

        COMMANDS:
            lint              Validate .gitlab-ci.yml syntax and semantics
            dag               Generate Graphviz DOT of pipeline DAG
            dry-run           Simulate pipeline execution against mock fleet
            help              Show this help message

        OPTIONS:
            --entry FILE      Path to CI config (default: ./.gitlab-ci.yml)
            --project DIR     Project directory (default: current directory)
            --runners DIR     Runner fleet directory (default: ./runners)
            --ref REF         Git ref to simulate (default: HEAD)
            --pipeline TYPE   Pipeline type: push|merge_request|schedule|manual (default: push)
            --variables K=V   Set CI variables (can be repeated)
            --env K=V         Set environment variables (alias for --variables)
            --undefined MODE  Handle undefined vars: warning|error|empty (default: warning)
            --verbose         Increase output verbosity
            --format FORMAT   Output format: text|json|junit (default: text)
            --gitlab-dir DIR  Path to GitLab submodule (default: ./gitlab)
            --help, -h        Show this help message
            --version, -v     Show version information

        EXAMPLES:
            gitlab_ci_cli lint
            gitlab_ci_cli dag | dot -Tpng -o pipeline.png
            gitlab_ci_cli dry-run --variables DEPLOY_ENV=staging
            gitlab_ci_cli lint --entry custom-ci.yml --verbose

        VERSION:
            #{VERSION}
      HELP
    end

    # Execute lint command
    # Returns: exit code
    def self.execute_lint(options)
      require_relative 'commands/lint_command'

      # Execute the lint command and get structured result
      result = Commands::LintCommand.execute(options)

      # Get appropriate formatter based on options
      formatter = create_formatter(options[:format])

      # Format and output the result
      output = formatter.format(result.to_h, command: :lint)
      puts output

      # Return the exit code from the result
      result.exit_code
    end

    # Execute dag command
    # Returns: exit code
    def self.execute_dag(options)
      require_relative 'commands/dag_command'

      command = DagCommand.new(options)
      dot_output = command.execute
      puts dot_output
      EXIT_SUCCESS
    rescue DagCommand::FileNotFoundError,
           DagCommand::InvalidConfigError,
           DagCommand::CircularDependencyError => e
      $stderr.puts "Error: #{e.message}"
      EXIT_COMMAND_FAILED
    end

    # Execute dry-run command
    # Returns: exit code
    def self.execute_dry_run(options)
      require_relative 'commands/dry_run_command'

      command = Commands::DryRunCommand.new(options)
      command.execute
    rescue StandardError => e
      $stderr.puts "Error: #{e.message}"
      $stderr.puts e.backtrace.join("\n") if options[:verbose]
      EXIT_COMMAND_FAILED
    end

    # Create a formatter instance based on format option
    # Returns: formatter instance
    def self.create_formatter(format)
      case format
      when 'text'
        require_relative 'formatters/text_formatter'
        Formatters::TextFormatter.new
      when 'json'
        require_relative 'formatters/json_formatter'
        Formatters::JsonFormatter.new
      when 'junit'
        require_relative 'formatters/junit_formatter'
        Formatters::JunitFormatter.new
      else
        # Should never reach here due to validation, but fail-fast anyway
        raise ArgumentError, "Unknown format: #{format}"
      end
    end
  end
end
