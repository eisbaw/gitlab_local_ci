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

# The one merge GitLab CI uses for both `include` and `extends`.
#
# Upstream (gitlab/ submodule) merges with ActiveSupport Hash#deep_merge! in
# External::Processor (includes) and Extendable::Entry#extend! (extends).
# Semantics: when both sides hold a Hash for a key, merge them recursively;
# otherwise the overlay value replaces the base value. Arrays are therefore
# REPLACED, never concatenated (yaml_optimization.md "Merge details").
# Key order follows Hash#merge: base keys keep their position, overlay-only
# keys are appended.
#
# The result shares no mutable structure with either input, so callers may
# reuse a base (e.g. one template extended by many jobs) safely.
module ConfigMerge
  module_function

  # @param base [Hash] lower-precedence configuration
  # @param overlay [Hash] higher-precedence configuration
  # @return [Hash] new merged hash
  def deep_merge(base, overlay)
    raise ArgumentError, "deep_merge base must be a Hash, got #{base.class}" unless base.is_a?(Hash)
    raise ArgumentError, "deep_merge overlay must be a Hash, got #{overlay.class}" unless overlay.is_a?(Hash)

    result = deep_dup(base)
    overlay.each do |key, value|
      result[key] = if result[key].is_a?(Hash) && value.is_a?(Hash)
                      deep_merge(result[key], value)
                    else
                      deep_dup(value)
                    end
    end
    result
  end

  def deep_dup(value)
    case value
    when Hash then value.to_h { |k, v| [k, deep_dup(v)] }
    when Array then value.map { |v| deep_dup(v) }
    when String then value.dup
    else value
    end
  end
end
