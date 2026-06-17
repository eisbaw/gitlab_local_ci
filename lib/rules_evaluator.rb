# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

require 'open3'

# RulesEvaluator evaluates a subset of GitLab CI `rules:` clauses
# (`if:`, `exists:`, `changes:`) against a variables hash and a project
# context. It is intentionally a partial port:
#
#   * `if:` grammar covers the cases real pipelines use (see grammar
#     below). It is NOT a full GitLab if-expression compiler.
#   * `exists:` uses `File.fnmatch?` with
#     `FNM_PATHNAME | FNM_DOTMATCH | FNM_EXTGLOB`, exactly matching
#     upstream gitlab/lib/gitlab/ci/build/rules/rule/clause/exists.rb.
#   * `changes:` shells out to `git diff --name-only` against either the
#     supplied `compare_to:` ref or `merge-base` with the default
#     branch. If git is unavailable or the diff fails, the clause
#     matches TRUE and a warning is emitted to stderr.
#
# REGEX ENGINE DIVERGENCE FROM UPSTREAM (Onigmo):
#   GitLab's runtime uses Ruby/Onigmo regex semantics. We compile via
#   Ruby's stock Regexp class — same engine in CRuby — so the common
#   cases are identical. However, gitlab_ci_local does NOT support the
#   following Onigmo-only constructs and will emit a Warning: to stderr
#   if it spots them in a user regex literal:
#
#     - lookbehind:      (?<=...) and (?<!...)
#     - named backref:   \k<name>
#     - numeric backref: \1 .. \9 inside the pattern
#     - atomic group:    (?>...)
#     - possessive:      *+ ++ ?+ {n,m}+
#
#   These ARE supported by Ruby's regex engine in practice; we still
#   warn because they are easy to mis-use across re2 / Onigmo / PCRE
#   boundaries — surface the divergence loudly rather than silently
#   accepting them.
#
# Supported `if:` grammar:
#   expr     := or_expr
#   or_expr  := and_expr ("||" and_expr)*
#   and_expr := cmp_expr ("&&" cmp_expr)*
#   cmp_expr := unary (("=="|"!="|"=~"|"!~") unary)?
#   unary    := "(" expr ")" | atom
#   atom     := variable | string | regex | "null"
#   variable := "$" identifier
#   string   := "..." | '...' (with $VAR / ${VAR} interpolation)
#   regex    := /.../flags (flags from [imsxU], with $VAR interpolation)
#
# Variable lookup semantics (match GitLab):
#   - Unset variables return nil. nil != "x" is TRUE.
#   - nil == null is TRUE; nil == "" is FALSE.
#   - "" =~ /.+/ is FALSE; "foo" =~ /.+/ is TRUE.
#   - bare `$VAR` is truthy iff value is a non-empty string.
class RulesEvaluator
  # Raised when a rule expression cannot be tokenized or parsed, or when
  # a clause violates the allowed schema for its rule context.
  class ParseError < StandardError; end

  # Allowed `when:` values for include-rules. Upstream:
  # gitlab/lib/gitlab/ci/config/external/rules.rb has
  # ALLOWED_WHEN = %w[never always]. Job-rules have a broader set.
  INCLUDE_RULE_ALLOWED_WHEN = %w[never always].freeze
  JOB_RULE_ALLOWED_WHEN = %w[on_success on_failure always manual delayed never].freeze

  # Keys recognized as non-clause attributes on a rule entry (everything
  # else after `if:`/`exists:`/`changes:`/`when:` becomes a job attribute
  # override when the rule matches). See upstream Rule#initialize.
  RULE_ATTRIBUTE_KEYS = %w[variables allow_failure start_in needs interruptible].freeze

  # Track one-time warnings (e.g. Onigmo-only constructs, U flag) so we
  # don't spam the user once per regex per rule.
  @warned = {}

  class << self
    attr_reader :warned

    # Reset memoized warning state. Test-only; production callers don't
    # need this, but specs assert on stderr output across examples.
    def reset_warnings!
      @warned = {}
    end
  end

  # Evaluate a list of `rules:` entries against the given variables and
  # context.
  #
  # @param rules [Array<Hash>, nil] List of rule entries.
  # @param variables [Hash, IndifferentHash] Variable lookup table.
  # @param context [Hash, nil] Optional context for non-`if:` clauses:
  #   { project_dir: String, default_branch: String }. If absent, the
  #   evaluator uses Dir.pwd / "main" as best-effort defaults.
  # @param mode [Symbol] :job (broad when:) or :include (when in
  #   {never, always} only). Default :job.
  # @return [Hash] {
  #     matched: Boolean,
  #     when: String|nil,        # rule's `when:` (caller-applied)
  #     attributes: Hash         # extracted RULE_ATTRIBUTE_KEYS overrides
  #   }
  def self.evaluate_rules(rules, variables, context: nil, mode: :job)
    return { matched: true, when: nil, attributes: {} } if rules.nil?

    unless rules.is_a?(Array)
      raise ParseError, "rules: must be a list, got #{rules.class}"
    end

    rules.each do |rule|
      next unless rule.is_a?(Hash)

      validate_when!(rule, mode)

      matched = rule_matches?(rule, variables, context)
      next unless matched

      return {
        matched: true,
        when: rule['when'] || rule[:when],
        attributes: extract_attributes(rule)
      }
    end

    { matched: false, when: nil, attributes: {} }
  end

  # Evaluate a single `if:` expression.
  #
  # @param expression [String] e.g. '$FOO == "bar"'
  # @param variables [Hash, IndifferentHash]
  # @return [Boolean]
  def evaluate(expression, variables)
    @tokens = tokenize(expression)
    @pos = 0
    @variables = variables || {}

    result = parse_or
    unless @pos >= @tokens.length
      raise ParseError, "Unexpected trailing tokens in rule expression: #{expression.inspect} (remaining: #{@tokens[@pos..].inspect})"
    end

    truthy?(result)
  end

  # --- Class-level clause helpers -----------------------------------------

  def self.rule_matches?(rule, variables, context)
    if_expr  = rule['if']      || rule[:if]
    exists   = rule['exists']  || rule[:exists]
    changes  = rule['changes'] || rule[:changes]

    # `if:` clause — if present, must evaluate true.
    if if_expr
      return false unless new.evaluate(if_expr.to_s, variables)
    end

    # `exists:` clause — match any pattern in the project tree.
    if exists
      return false unless exists_matches?(exists, variables, context)
    end

    # `changes:` clause — match any pattern against changed paths.
    if changes
      return false unless changes_matches?(changes, variables, context)
    end

    # An empty rule (no if/exists/changes) is an unconditional match —
    # consistent with GitLab and the existing behavior.
    true
  end

  def self.exists_matches?(spec, variables, context)
    patterns = extract_patterns(spec, key: :exists)
    return false if patterns.empty?

    project_dir = (context && context[:project_dir]) || Dir.pwd
    expanded = patterns.map { |p| interpolate(p, variables) }

    # Mirror upstream: walk all files under project_dir and try fnmatch.
    # Cap iteration to avoid pathological globs in huge trees — upstream
    # uses MAX_PATTERN_COMPARISONS=10_000 and bails to true; we cap the
    # walk itself at 50_000 files for safety.
    paths = []
    base = File.expand_path(project_dir)
    Dir.glob('**/*', File::FNM_DOTMATCH, base: base).each do |rel|
      next if rel == '.' || rel == '..' || rel.end_with?('/..') || rel.end_with?('/.')
      paths << rel
      break if paths.size > 50_000
    end

    expanded.any? do |glob|
      paths.any? do |path|
        File.fnmatch?(glob, path, File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB)
      end
    end
  end

  def self.changes_matches?(spec, variables, context)
    patterns = extract_patterns(spec, key: :changes)
    return false if patterns.empty?

    project_dir    = (context && context[:project_dir])    || Dir.pwd
    default_branch = (context && context[:default_branch]) || 'main'
    compare_to     = spec.is_a?(Hash) ? (spec['compare_to'] || spec[:compare_to]) : nil
    compare_to     = interpolate(compare_to.to_s, variables) if compare_to

    diff = git_changed_paths(project_dir, default_branch, compare_to)
    if diff.nil?
      warn_once("changes: git diff unavailable in #{project_dir.inspect}; matching TRUE")
      return true
    end

    expanded = patterns.map { |p| interpolate(p, variables) }
    expanded.any? do |glob|
      diff.any? do |path|
        File.fnmatch?(glob, path, File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB)
      end
    end
  end

  # Return Array<String> of changed paths versus the compare ref. Falls
  # back to merge-base with the default branch. Returns nil if git is
  # unavailable or the diff fails — caller should treat that as
  # "match-true with warning".
  def self.git_changed_paths(project_dir, default_branch, compare_to)
    # Allow caller to specify compare ref explicitly.
    base_ref =
      if compare_to && !compare_to.empty?
        compare_to
      else
        # merge-base with default branch (best effort)
        out, _e, st = Open3.capture3('git', '-C', project_dir, 'merge-base', "HEAD", default_branch)
        st.success? ? out.strip : nil
      end

    return nil if base_ref.nil? || base_ref.empty?

    # `git diff --name-only base...HEAD` — committed differences.
    committed_out, _e, committed_st = Open3.capture3(
      'git', '-C', project_dir, 'diff', '--name-only', "#{base_ref}...HEAD"
    )
    return nil unless committed_st.success?

    # Also include uncommitted modifications — local dirty-tree edits
    # should be visible to `changes:` during `dry-run`, otherwise the
    # tool only sees changes that are already pushed.
    uncommitted_out, _e2, uncommitted_st = Open3.capture3(
      'git', '-C', project_dir, 'diff', '--name-only', 'HEAD'
    )
    uncommitted = uncommitted_st.success? ? uncommitted_out.split("\n") : []

    (committed_out.split("\n") + uncommitted).map(&:strip).reject(&:empty?).uniq
  rescue StandardError
    nil
  end

  def self.extract_patterns(spec, key:)
    return [] if spec.nil?

    if spec.is_a?(Array)
      spec.map(&:to_s)
    elsif spec.is_a?(Hash)
      paths = spec['paths'] || spec[:paths]
      Array(paths).map(&:to_s)
    elsif spec.is_a?(String)
      # GitLab accepts `exists: "single-pattern"` shorthand too.
      [spec]
    else
      raise ParseError, "#{key}: must be an array, hash with paths:, or string; got #{spec.class}"
    end
  end

  def self.extract_attributes(rule)
    out = {}
    RULE_ATTRIBUTE_KEYS.each do |k|
      # Use key? to honor `false` values (e.g. interruptible: false).
      if rule.key?(k)
        out[k] = rule[k]
      elsif rule.key?(k.to_sym)
        out[k] = rule[k.to_sym]
      end
    end
    out
  end

  def self.validate_when!(rule, mode)
    w = rule['when'] || rule[:when]
    return if w.nil?

    case mode
    when :include
      unless INCLUDE_RULE_ALLOWED_WHEN.include?(w.to_s)
        raise ParseError,
              "include: rules:when value '#{w}' is not allowed; must be one of: " \
              "#{INCLUDE_RULE_ALLOWED_WHEN.join(', ')}"
      end
    when :job
      unless JOB_RULE_ALLOWED_WHEN.include?(w.to_s)
        raise ParseError,
              "rules:when value '#{w}' is not allowed; must be one of: " \
              "#{JOB_RULE_ALLOWED_WHEN.join(', ')}"
      end
    end
  end

  def self.warn_once(message)
    @warned ||= {}
    return if @warned[message]
    @warned[message] = true
    warn "Warning: #{message}"
  end

  # Interpolate $VAR / ${VAR} against `variables`. Unset names expand to
  # empty string. Used by string + regex literal expansion, and by
  # exists:/changes: pattern expansion.
  def self.interpolate(str, variables)
    return str if str.nil?
    s = str.to_s
    # ${VAR}
    s = s.gsub(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/) do
      lookup(variables, Regexp.last_match(1)).to_s
    end
    # $VAR — match longest identifier
    s.gsub(/\$([A-Za-z_][A-Za-z0-9_]*)/) do
      lookup(variables, Regexp.last_match(1)).to_s
    end
  end

  def self.lookup(variables, name)
    return variables[name] if variables.respond_to?(:[]) && (variables[name] || variables.respond_to?(:key?) && variables.key?(name))
    nil
  end

  private

  # --- Lexer ---------------------------------------------------------------

  TOKEN_PATTERNS = [
    [:WS,       /\A\s+/],
    [:LPAREN,   /\A\(/],
    [:RPAREN,   /\A\)/],
    [:AND,      /\A&&/],
    [:OR,       /\A\|\|/],
    [:EQ,       /\A==/],
    [:NEQ,      /\A!=/],
    [:MATCH,    /\A=~/],
    [:NMATCH,   /\A!~/],
    [:NULL,     /\Anull\b/],
    [:VAR,      /\A\$([A-Za-z_][A-Za-z0-9_]*)/],
    # Regex literal: /pattern/flags. Pattern may contain escaped slashes.
    # Flags are captured loosely; validation happens in build_regex.
    [:REGEX,    %r{\A/((?:\\.|[^/\\])*)/([A-Za-z]*)}],
    # Double-quoted string with simple backslash escapes.
    [:STRING_D, /\A"((?:\\.|[^"\\])*)"/],
    # Single-quoted string with simple backslash escapes.
    [:STRING_S, /\A'((?:\\.|[^'\\])*)'/],
  ].freeze

  def tokenize(expr)
    tokens = []
    s = expr.dup

    until s.empty?
      matched = false
      TOKEN_PATTERNS.each do |type, pattern|
        m = s.match(pattern)
        next unless m

        case type
        when :WS
          # discard
        when :VAR
          tokens << [:VAR, m[1]]
        when :REGEX
          tokens << [:REGEX, [m[1], m[2]]]
        when :STRING_D, :STRING_S
          tokens << [:STRING, unescape(m[1])]
        else
          tokens << [type, m[0]]
        end

        s = m.post_match
        matched = true
        break
      end

      raise ParseError, "Cannot tokenize at: #{s.inspect}" unless matched
    end

    tokens
  end

  def unescape(str)
    str.gsub(/\\(.)/) do
      case Regexp.last_match(1)
      when 'n' then "\n"
      when 't' then "\t"
      when 'r' then "\r"
      else Regexp.last_match(1)
      end
    end
  end

  # --- Parser --------------------------------------------------------------

  def peek
    @tokens[@pos]
  end

  def consume(expected_type = nil)
    tok = @tokens[@pos]
    if expected_type && (tok.nil? || tok[0] != expected_type)
      raise ParseError, "Expected #{expected_type}, got #{tok.inspect}"
    end
    @pos += 1
    tok
  end

  def parse_or
    left = parse_and
    while peek && peek[0] == :OR
      consume(:OR)
      right = parse_and
      left = truthy?(left) || truthy?(right)
    end
    left
  end

  def parse_and
    left = parse_cmp
    while peek && peek[0] == :AND
      consume(:AND)
      right = parse_cmp
      left = truthy?(left) && truthy?(right)
    end
    left
  end

  def parse_cmp
    left = parse_unary
    tok = peek
    return left unless tok && %i[EQ NEQ MATCH NMATCH].include?(tok[0])

    op = consume[0]
    right = parse_unary

    case op
    when :EQ     then values_equal?(left, right)
    when :NEQ    then !values_equal?(left, right)
    when :MATCH  then regex_match?(left, right)
    when :NMATCH then !regex_match?(left, right)
    end
  end

  def parse_unary
    tok = peek
    raise ParseError, "Unexpected end of expression" if tok.nil?

    case tok[0]
    when :LPAREN
      consume(:LPAREN)
      val = parse_or
      consume(:RPAREN)
      val
    when :VAR
      consume
      lookup_var(tok[1])
    when :STRING
      consume
      # GAP 7: interpolate $VAR / ${VAR} in string literals at eval-time
      RulesEvaluator.interpolate(tok[1], @variables)
    when :REGEX
      consume
      build_regex(tok[1][0], tok[1][1])
    when :NULL
      consume
      nil
    else
      raise ParseError, "Unexpected token: #{tok.inspect}"
    end
  end

  # --- Helpers -------------------------------------------------------------

  def lookup_var(name)
    if @variables.respond_to?(:[])
      v = @variables[name]
      return v unless v.nil?
    end
    if @variables.respond_to?(:key?) && @variables.key?(name)
      @variables[name]
    else
      nil
    end
  end

  # Build a Regexp from a literal pattern + flag string.
  #
  # Supported flags: [imsxU]
  #   i — case-insensitive            (Regexp::IGNORECASE)
  #   m — multiline (. matches \n)    (Regexp::MULTILINE)
  #   s — same as m for GitLab parity (.matches \n)
  #   x — extended (whitespace/comments) — DIVERGES from upstream
  #       Onigmo, which uses x for a slightly different extended syntax.
  #       In practice the difference rarely matters for rule expressions.
  #   U — Onigmo ungreedy. Ruby has no direct toggle that flips default
  #       greedy quantifiers to ungreedy without rewriting the pattern,
  #       so we ACCEPT the flag, emit a one-time warning, and treat it
  #       as a no-op. Patterns relying on U semantics will misbehave.
  #
  # Unknown flag chars raise ParseError.
  def build_regex(source, flags)
    expanded_source = RulesEvaluator.interpolate(source, @variables)

    # Validate flag chars and warn on Onigmo-only constructs.
    flags.each_char do |c|
      unless %w[i m s x U].include?(c)
        raise ParseError, "Unknown regex flag '#{c}' in /#{source}/#{flags}"
      end
    end

    if flags.include?('U')
      RulesEvaluator.warn_once(
        "regex flag 'U' (Onigmo ungreedy) is accepted but treated as no-op — " \
        "Ruby Regexp has no equivalent toggle; quantifier greediness preserved"
      )
    end

    detect_onigmo_only_constructs!(expanded_source)

    options = 0
    options |= Regexp::IGNORECASE if flags.include?('i')
    options |= Regexp::MULTILINE  if flags.include?('m')
    options |= Regexp::MULTILINE  if flags.include?('s')
    options |= Regexp::EXTENDED   if flags.include?('x')
    Regexp.new(expanded_source, options)
  end

  # Emit a Warning: to stderr (once per construct+pattern) if the user
  # regex uses a construct that diverges across Onigmo / re2 / PCRE.
  # Ruby's Regexp accepts them, but flagging the divergence is the
  # contract.
  def detect_onigmo_only_constructs!(pattern)
    [
      ['(?<=', "lookbehind '(?<=...)'"],
      ['(?<!', "negative lookbehind '(?<!...)'"],
      ['(?>',  "atomic group '(?>...)'"],
      ['\\k<', "named backreference '\\k<...>'"],
    ].each do |needle, label|
      if pattern.include?(needle)
        RulesEvaluator.warn_once("regex uses Onigmo construct: #{label} in /#{pattern}/")
      end
    end

    # Numeric backref \1..\9 (not preceded by another backslash).
    if pattern =~ /(?<!\\)\\[1-9]/
      RulesEvaluator.warn_once("regex uses Onigmo construct: numeric backreference in /#{pattern}/")
    end

    # Possessive quantifier: *+ ++ ?+ {n,m}+ — require that the leading
    # char is one of the quantifier metacharacters.
    if pattern =~ /(?<!\\)[*+?]\+/ || pattern =~ /\}\+/
      RulesEvaluator.warn_once("regex uses Onigmo construct: possessive quantifier in /#{pattern}/")
    end
  end

  # GitLab semantics: nil and string compared by Ruby equality.
  def values_equal?(a, b)
    a == b
  end

  def regex_match?(value, pattern)
    pattern_regex = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern.to_s)
    return false if value.nil?

    !pattern_regex.match(value.to_s).nil?
  end

  def truthy?(value)
    case value
    when true, false then value
    when nil         then false
    when String      then !value.empty?
    else true
    end
  end
end
