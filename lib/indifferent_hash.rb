# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

# IndifferentHash: a small wrapper that exposes a Hash with String/Symbol
# key indifference for the read paths we need.
#
# Upstream GitLab uses ActiveSupport::HashWithIndifferentAccess, but
# gitlab_ci_local does NOT depend on ActiveSupport (see Gemfile.lock —
# only rspec, simplecov, gitlab gem). Pulling in AS just for this would
# be a heavy transitive dep, so we ship a minimal shim instead.
#
# Semantics:
#   - Writes go through with the supplied key normalized to a String.
#   - Reads look up the string-normalized key.
#   - `key?` / `include?` / `[]` / `fetch` / `merge` / `each` are
#     supported; nested hashes are NOT recursively wrapped (we only need
#     top-level indifference for the var/attribute tables this serves).
#
# This intentionally does not implement the full HashWithIndifferentAccess
# API. If you need recursive indifference, extend with care.
class IndifferentHash
  include Enumerable

  def self.wrap(obj)
    return obj if obj.is_a?(IndifferentHash)
    new(obj || {})
  end

  def initialize(hash = {})
    @h = {}
    hash.each { |k, v| @h[k.to_s] = v }
  end

  def [](key)
    @h[key.to_s]
  end

  def []=(key, value)
    @h[key.to_s] = value
  end

  def key?(key)
    @h.key?(key.to_s)
  end
  alias_method :include?, :key?
  alias_method :has_key?, :key?

  def fetch(key, *args, &block)
    @h.fetch(key.to_s, *args, &block)
  end

  def delete(key)
    @h.delete(key.to_s)
  end

  def merge(other)
    other_hash = other.is_a?(IndifferentHash) ? other.to_h : other
    result = IndifferentHash.new(@h)
    other_hash.each { |k, v| result[k.to_s] = v }
    result
  end

  def merge!(other)
    other_hash = other.is_a?(IndifferentHash) ? other.to_h : other
    other_hash.each { |k, v| @h[k.to_s] = v }
    self
  end

  def each(&block)
    @h.each(&block)
  end

  def keys
    @h.keys
  end

  def values
    @h.values
  end

  def empty?
    @h.empty?
  end

  def size
    @h.size
  end
  alias_method :length, :size

  def to_h
    @h.dup
  end

  def to_hash
    @h.dup
  end

  def ==(other)
    case other
    when IndifferentHash then to_h == other.to_h
    when Hash then to_h == other.transform_keys(&:to_s)
    else false
    end
  end
end
