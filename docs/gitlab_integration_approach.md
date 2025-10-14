# GitLab Integration Approach

## Summary

Successfully integrated GitLab's CI YAML processing classes into MockServer following MPED architectural principles. The integration uses GitLab v17.5.0-ee classes without modification through Ruby load path injection.

## Implementation Details

### 1. Load Path Setup (lib/mock_server.rb)

**Approach**: Dependency injection with fail-fast validation

```ruby
def setup_gitlab_load_path
  gitlab_lib_path = File.join(@gitlab_path, 'lib')
  unless File.directory?(gitlab_lib_path)
    raise ArgumentError, "GitLab lib directory not found at #{gitlab_lib_path}"
  end
  $LOAD_PATH.unshift(gitlab_lib_path) unless $LOAD_PATH.include?(gitlab_lib_path)
end
```

**MPED Principles Applied**:
- Dependency injection: `gitlab_path` passed as parameter, not hardcoded
- Fail-fast: Immediate validation that path exists
- Clear error messages: Explains exactly what is missing
- No side effects: Only modifies load path if not already present

### 2. GitLab Class Loading (lib/mock_server.rb)

**Approach**: Explicit requires with error handling

```ruby
def load_gitlab_classes
  require 'gitlab/ci/yaml_processor'
  require 'gitlab/ci/config'
  require 'gitlab/ci/yaml_processor/dag'
rescue LoadError => e
  raise LoadError, "Failed to load GitLab CI classes: #{e.message}. " \
                   "Ensure GitLab submodule is initialized at #{@gitlab_path}"
end
```

**MPED Principles Applied**:
- Explicit dependencies: Only require what we need
- Fail-fast: LoadError converted to clear actionable message
- No monkey-patching: Use GitLab classes as-is
- Reproducibility: Same load order every time

### 3. YAML Processing Integration (lib/mock_server.rb)

**Approach**: Thin wrapper around GitLab's YamlProcessor

```ruby
def create_pipeline(config, options = {})
  config_content = config.is_a?(String) ? config : config.to_yaml

  processor = Gitlab::Ci::YamlProcessor.new(config_content, **build_processor_options(options))
  result = processor.execute

  if result.errors.any?
    raise ConfigurationError, "Configuration errors:\n" + result.errors.join("\n")
  end

  ci_config = result.ci_config
  stages = ci_config.stages
  jobs = ci_config.normalized_jobs

  validate_dag(jobs)
  # ... build pipeline object
end
```

**MPED Principles Applied**:
- Composability: YamlProcessor used as library, not framework
- Single source of truth: GitLab processor is the only YAML parser
- Fail-fast: Errors propagated immediately with context
- Data design first: Extract stages and jobs from processor result
- No derived state: Parse once, use results directly

### 4. DAG Validation (lib/mock_server.rb)

**Approach**: Use GitLab's built-in DAG validator without modification

```ruby
def validate_dag(jobs)
  job_dependencies = jobs.transform_values do |job|
    needs = job.dig(:needs, :job)
    needs ? needs.map { |need| need[:name].to_s } : []
  end.transform_keys(&:to_s)

  Gitlab::Ci::YamlProcessor::Dag.check_circular_dependencies!(job_dependencies)
rescue Gitlab::Ci::YamlProcessor::ValidationError => e
  raise ConfigurationError, "DAG validation failed: #{e.message}"
end
```

**MPED Principles Applied**:
- Reuse upstream logic: No reimplementation of circular dependency detection
- Data transformation: Convert to format expected by upstream validator
- Clear error propagation: Wrap upstream errors with context
- Fail-fast: Validation before pipeline creation

### 5. Mock Project Handling (lib/mock_server.rb)

**Approach**: Minimal mock, rely on GitLab's optional project handling

```ruby
def build_processor_options(options)
  opts = {}
  opts[:project] = nil  # GitLab handles nil project gracefully
  opts[:sha] = options[:sha] if options[:sha]
  opts[:ref] = options[:ref] if options[:ref]
  opts[:user] = nil
  opts
end
```

**MPED Principles Applied**:
- Minimal state: No complex mock objects
- Use what works: GitLab processor works without project in most cases
- Future extensibility: Can add minimal mock project if needed
- Bottom-up: Start simple, add complexity only when required

## Challenges with GitLab API

### 1. Project Dependency

**Challenge**: Many GitLab classes expect a Project ActiveRecord model with repository, user permissions, and database backing.

**Solution**: Pass `nil` for project and rely on GitLab's defensive coding. Most YAML processing works without project context. For features requiring project (like ref validation), we skip those validations in local mode.

**Trade-off**: Some validations (like checking if SHA exists in repository) are skipped. This is acceptable for local simulation where we trust user input.

### 2. Rails Dependencies

**Challenge**: GitLab classes assume Rails environment (ActiveSupport, Rails.cache, etc.).

**Current State**: These dependencies are lazy-loaded, so basic YAML processing works. Full integration may require:
- Stubbing Rails.cache
- Loading ActiveSupport extensions
- Mocking logger

**Mitigation**: Load GitLab classes at runtime, fail fast if dependencies missing. Document which GitLab features work without Rails.

### 3. Database Models

**Challenge**: Ci::Pipeline, Ci::Build, and other models expect database persistence.

**Solution**: Created MockPipeline and MockJob that hold same data structure but with in-memory state. These mirror GitLab's model structure without ActiveRecord.

**MPED Alignment**: Single source of truth (job array), no derived state storage, state computed on demand.

### 4. Complex Job Configuration

**Challenge**: GitLab normalizes jobs through many layers (Config::Entry, Normalizer, etc.).

**Solution**: Use `ci_config.normalized_jobs` which provides fully processed job definitions. Extract only what we need (stage, script, needs, tags).

**MPED Alignment**: Let GitLab do the work, don't reimplement normalization logic.

## MPED Principle Adherence

### Fundamentals First
- Git submodule for reproducible GitLab version
- Ruby load path manipulation (standard, well-understood)
- No patching: use GitLab as-is

### Composability
- GitLab classes used as libraries, not frameworks
- MockServer composes YamlProcessor, Config, Dag validator
- Each component has single responsibility

### Data Design Before Algorithms
- Pipeline state derived from job states (no duplicate storage)
- Jobs are single source of truth for pipeline status
- Immutable data where possible (stages, ref frozen)

### Fail Fast and Verbosely
- Immediate validation of gitlab_path on initialization
- Clear error messages with actionable guidance
- LoadError converted to "ensure GitLab submodule initialized"
- ConfigurationError lists all YAML validation errors

### Minimize State, Never Duplicate
- No cached/derived pipeline status (computed from jobs)
- Jobs hold state, pipeline derives status
- No duplicate job metadata storage

### Optimize for Readability First
- Clear method names: `setup_gitlab_load_path`, `validate_dag`
- Inline comments explain GitLab API quirks
- Methods under 30 lines
- One responsibility per method

### Bottom-Up Development
- Started with load path setup (test first)
- Added YAML parsing (verify with simple config)
- Added DAG validation (test with circular deps)
- Can incrementally add features (runner matching, job execution)

## Testing Strategy

Integration test verifies:
1. GitLab classes load successfully from submodule
2. Valid YAML parsed correctly into pipeline/jobs
3. Circular dependencies detected
4. Invalid YAML produces clear errors
5. Pipeline state transitions work

Next steps for testing:
- Test with complex GitLab features (includes, extends, anchors)
- Test variable interpolation
- Test job scheduling with needs
- Test with real .gitlab-ci.yml files from open source projects

## Future Enhancements

### Short-term
1. Add mock project when needed for ref validation
2. Stub Rails.cache for features that require it
3. Handle more job attributes (when/rules, allow_failure)

### Long-term
1. Integrate Ci::ProcessPipelineService for state machine
2. Integrate Ci::RegisterJobService for runner job matching
3. Handle child pipelines and includes
4. Support upstream/downstream pipeline triggers

## Conclusion

The GitLab integration successfully demonstrates MPED principles:
- Zero patches to upstream code
- Clear separation between our code and GitLab code
- Fail-fast validation throughout
- Composable design that can evolve
- Bottom-up approach: start simple, add complexity incrementally

The thin wrapper approach means:
- Easy to upgrade GitLab submodule (no patches to merge)
- Inherits GitLab's YAML processing improvements automatically
- Minimal maintenance burden
- Clear boundaries between mock and real code
