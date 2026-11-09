# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require_relative 'ci_yaml'
require_relative 'config_merge'

# Replaces every CiYaml::Reference in a config with the value it points at,
# like upstream Config::Yaml::Tags::Resolver + Tags::Reference
# (gitlab/ submodule, lib/gitlab/ci/config/yaml/tags/):
#
# - Runs once on the whole config after includes and extends, so a
#   reference sees merged files and a template's extended result.
# - A path is looked up in that same (unresolved) config, Hash keys only,
#   then resolved recursively, so references may nest.
# - Errors, upstream's texts:
#     !reference ["a", "b"] is not valid          (not a non-empty list of strings)
#     !reference ["a", "b"] is part of a circular chain
#     !reference ["a", "b"] could not be found     (missing, nil or false target)
#
# Upstream has no depth limit on nested references beyond the cycle check;
# neither does this: every path on the resolution stack is distinct and
# present in the config, so recursion depth is bounded by the number of
# distinct reference paths.
class ReferenceResolver
  Error = Class.new(StandardError)

  # @param config [Hash] configuration after includes and extends
  # @return [Hash] new configuration without References
  # @raise [Error] with upstream's message
  def self.resolve(config)
    raise ArgumentError, "config must be a Hash, got #{config.class}" unless config.is_a?(Hash)

    new(config).deep_resolve(config)
  end

  def initialize(config)
    @config = config
    @in_progress = [] # paths being resolved, outermost first
    @resolved = {}    # path => resolved value; one lookup per path
  end

  def deep_resolve(value)
    case value
    when Hash then value.transform_values { |item| deep_resolve(item) }
    when Array then value.map { |item| deep_resolve(item) }
    # A copy per use site, so two references to one path share nothing.
    when CiYaml::Reference then ConfigMerge.deep_dup(resolve_reference(value))
    else value
    end
  end

  private

  def resolve_reference(reference)
    raise Error, "#{reference} is not valid" unless reference.valid?

    path = reference.data
    raise Error, "#{reference} is part of a circular chain" if @in_progress.include?(path)

    @resolved.fetch(path) do
      @in_progress.push(path)
      value = deep_resolve(lookup(reference))
      @in_progress.pop
      raise Error, "#{reference} could not be found" unless value

      @resolved[path] = value
    end
  end

  # Upstream config.dig(*path): only Hashes are walked; anything else on
  # the way (a list, a string, another unresolved reference) is not found.
  def lookup(reference)
    reference.data.reduce(@config) do |node, key|
      break nil if node.nil?
      raise Error, "#{reference} could not be found" unless node.is_a?(Hash)

      node[key]
    end
  end
end
