# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require_relative 'formatters/base_formatter'
require_relative 'formatters/text_formatter'
require_relative 'formatters/json_formatter'
require_relative 'formatters/junit_formatter'
require_relative 'formatters/formatter_factory'

# Module for output formatters
# Provides text, JSON, and JUnit formatters for command output
module Formatters
end
