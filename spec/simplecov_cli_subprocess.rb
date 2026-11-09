# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

# Coverage for bin/gitlab_ci_cli runs spawned by the integration specs.
#
# spec_helper.rb puts `-r<this file>` on RUBYOPT, so every Ruby process the
# suite spawns loads it. Only the CLI is measured: job scripts run by
# `run` may start other Ruby programs, and those are not ours.
#
# The child is silent (several specs assert an empty stderr) and checks no
# minimum; it only stores its result. The rspec process merges all results
# and applies the gate.
return unless $PROGRAM_NAME.end_with?('bin/gitlab_ci_cli')

# A bare require 'simplecov' makes RubyGems scan every spec, and in the dev
# shell that prints "Ignoring ... extensions are not built" to the CLI's
# stderr (TASK-30). Activating by name loads only simplecov's dependency
# chain, the same mitigation as gem 'rexml' in junit_formatter.rb.
gem 'simplecov'
require_relative 'simplecov_config'

SimpleCov.command_name("cli subprocess #{Process.pid}")
SimpleCov.coverage_dir(File.join(SimpleCovConfig::SUBPROCESS_DIR, Process.pid.to_s))
SimpleCov.print_error_status = false
SimpleCov.at_exit { SimpleCov.result }
SimpleCov.start { SimpleCovConfig.apply_common }
