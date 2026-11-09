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

# Quoting text as one POSIX shell word. Not Shellwords.escape: that
# backslash-escapes, which is unreadable in generated scripts and error
# messages; a single-quoted word is read back verbatim.
module ShellQuote
  module_function

  # Single-quoted for a POSIX shell: nothing inside is expanded, so the
  # word reads back as exactly `text`, newlines included.
  #
  # @param text [String]
  # @return [String]
  # @raise [ArgumentError] text contains NUL, which no shell word can hold
  #   (bash would silently truncate there)
  def quote(text)
    raise ArgumentError, "cannot shell-quote a string containing NUL: #{text.inspect}" if text.include?("\0")

    "'#{text.gsub("'") { %q('\\'') }}'"
  end
end
