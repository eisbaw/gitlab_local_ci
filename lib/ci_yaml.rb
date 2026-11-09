# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require 'psych'

# The one loader for .gitlab-ci.yml content: the entry file
# (PipelineBuilder.load_yaml) and every included file (IncludeProcessor).
#
# Same as YAML.safe_load(content, permitted_classes: [Symbol], aliases: true)
# except that a node tagged `!reference` becomes a CiYaml::Reference instead
# of losing its tag. Without that, `!reference [.setup, script]` is
# indistinguishable from the literal list [".setup", "script"].
# ReferenceResolver replaces every Reference after extends, as upstream does
# (Config::Yaml::Loader registers Tags::Reference with Psych, then
# Tags::Resolver runs after Extendable).
#
# Upstream registers the tag globally (Psych.add_tag); this loader keeps it
# local to its own visitor so other YAML.safe_load callers are unaffected.
module CiYaml
  REFERENCE_TAG = '!reference'

  # An unresolved `!reference` tag. data is the tagged node as Ruby: a
  # list of key names when valid (upstream Tags::Reference#valid?).
  # Immutable, so ConfigMerge.deep_dup may share it between copies.
  Reference = Data.define(:data) do
    def valid?
      data.is_a?(Array) && !data.empty? && data.all?(String)
    end

    # Upstream's spelling of the tag in its error messages.
    def to_s
      "#{REFERENCE_TAG} #{data.inspect}"
    end
  end

  # Psych's safe_load visitor with !reference nodes turned into References.
  # register keeps YAML anchors on a tagged node working.
  class Visitor < Psych::Visitors::ToRuby
    def visit_Psych_Nodes_Sequence(node)
      return super unless node.tag == REFERENCE_TAG

      register(node, Reference.new(data: node.children.map { |child| accept(child) }.freeze))
    end

    def visit_Psych_Nodes_Scalar(node)
      return super unless node.tag == REFERENCE_TAG

      register(node, Reference.new(data: node.value.dup.freeze))
    end

    def visit_Psych_Nodes_Mapping(node)
      return super unless node.tag == REFERENCE_TAG

      pairs = node.children.each_slice(2).map { |key, value| [accept(key), accept(value)] }
      register(node, Reference.new(data: pairs.to_h.freeze))
    end
  end

  module_function

  # @param content [String] YAML text
  # @return [Object] parsed document, nil if empty
  # @raise [Psych::SyntaxError] invalid YAML
  # @raise [Psych::DisallowedClass] a tag safe_load would reject too
  def load(content)
    document = Psych.parse(content)
    return nil unless document

    class_loader = Psych::ClassLoader::Restricted.new(['Symbol'], [])
    scanner = Psych::ScalarScanner.new(class_loader, strict_integer: false)
    Visitor.new(scanner, class_loader, symbolize_names: false, freeze: false).accept(document)
  end
end
