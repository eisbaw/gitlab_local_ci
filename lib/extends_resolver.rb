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

require_relative 'config_merge'

# Resolves `extends:` like upstream Config::Extendable (gitlab/ submodule,
# lib/gitlab/ci/config/extendable{,/entry}.rb):
#
# - Every top-level key is a root (Extendable#each), hidden templates and
#   global keys included, so errors in a template no job uses are raised and
#   a template's merged result is what a later `!reference` sees.
# - Parents are resolved recursively, deep-merged in `extends:` order (later
#   parent wins), then the entry's own keys on top. The merge is ConfigMerge,
#   the one includes use: hashes merge, arrays replace.
# - Each merged entry is written back at its own position.
# - Checks and their texts are upstream's, in upstream's order: unknown
#   keys, invalid base hashes, nesting too deep, circular dependency.
#
# Deliberate difference: the `extends` key is removed from the merged entry.
# Upstream keeps it in the hash but no Entry exposes it as a job value, and
# every consumer here reads this hash as job values.
class ExtendsResolver
  ExtensionError = Class.new(StandardError)
  NestingTooDeepError = Class.new(ExtensionError)
  CircularDependencyError = Class.new(ExtensionError)
  InvalidExtensionError = Class.new(ExtensionError)

  # Upstream Extendable::Entry::MAX_NESTING_LEVELS: an entry with more than
  # this many ancestors may not itself extend, i.e. 11 levels are allowed.
  MAX_NESTING_LEVELS = 10

  # @param config [Hash] configuration after includes
  # @return [Hash] new configuration, every extensible entry merged, key order kept
  # @raise [ExtensionError] with upstream's message
  def resolve_extends(config)
    raise ArgumentError, "config must be a Hash, got #{config.class}" unless config.is_a?(Hash)

    @config = config
    # key => merged entry, and key => longest extends chain (edges) below it.
    # Memoised so a template shared by many entries is merged once instead of
    # once per path (fan-out^depth).
    @resolved = {}
    @height = {}
    config.each_key { |key| extend_entry(key, []) }
    config.to_h { |key, value| [key, @resolved.fetch(key, value)] }
  end

  private

  def extensible?(value)
    value.is_a?(Hash) && value.key?('extends')
  end

  # Upstream Entry#extend!. ancestors are the entries that extend
  # (transitively) into key, root first.
  #
  # @return [Hash, Object] merged entry, or the value itself if not extensible
  def extend_entry(key, ancestors)
    value = @config.fetch(key)
    return value unless extensible?(value)
    return @resolved.fetch(key) if memo_valid?(key, ancestors)

    parent_keys = Array(value['extends']).map(&:to_s)
    check_entry!(key, parent_keys, ancestors)

    merged = parent_keys.reduce({}) do |acc, parent_key|
      ConfigMerge.deep_merge(acc, extend_entry(parent_key, ancestors + [key]))
    end
    result = ConfigMerge.deep_merge(merged, value)
    result.delete('extends')

    @height[key] = 1 + parent_keys.map { |parent_key| @height.fetch(parent_key, 0) }.max.to_i
    @resolved[key] = result
  end

  # A memoised entry is only reusable if upstream, re-walking it from here,
  # would not hit the nesting limit: its deepest extensible descendant sits
  # at ancestors.size + height - 1. Otherwise fall through and re-walk, so
  # the error names the same entry upstream's walk would.
  def memo_valid?(key, ancestors)
    @resolved.key?(key) && ancestors.size + @height.fetch(key) - 1 <= MAX_NESTING_LEVELS
  end

  def check_entry!(key, parent_keys, ancestors)
    unknown = parent_keys.reject { |parent_key| @config.key?(parent_key) }
    unless unknown.empty?
      raise InvalidExtensionError, "#{key}: unknown keys in `extends` (#{unknown.join(', ')})"
    end

    invalid = parent_keys.reject { |parent_key| @config[parent_key].is_a?(Hash) }
    unless invalid.empty?
      raise InvalidExtensionError, "#{key}: invalid base hashes in `extends` (#{invalid.join(', ')})"
    end

    raise NestingTooDeepError, "#{key}: nesting too deep in `extends`" if ancestors.size > MAX_NESTING_LEVELS
    raise CircularDependencyError, "#{key}: circular dependency detected in `extends`" if ancestors.include?(key)
  end
end
