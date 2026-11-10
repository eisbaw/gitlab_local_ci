# Usage

Reference for the `gitlab_ci_cli` commands. The [README](../README.md) has the
overview and a first session; [runners.md](runners.md) the runner fleet format.

- [Commands](#commands)
- [Predefined variables](#predefined-variables)
- [Includes](#includes)
- [Parallel jobs](#parallel-jobs)
- [Running jobs: run and export-just](#running-jobs-run-and-export-just)
- [CLI reference](#cli-reference)
- [Troubleshooting](#troubleshooting)

## Commands

### Lint Command

Validate `.gitlab-ci.yml` syntax and semantics:

```bash
# Basic validation
gitlab_ci_cli lint --entry .gitlab-ci.yml

# JSON output format
gitlab_ci_cli lint --entry .gitlab-ci.yml --format json

# JUnit XML output (useful for CI integration)
gitlab_ci_cli lint --entry .gitlab-ci.yml --format junit
```

**Example output:**
```
GitLab CI configuration is valid
Stages: .pre, build, test, deploy, .post
Jobs: 5
```

**What lint validates:**
- ✅ YAML syntax errors
- ✅ Job structure (script, stage, needs, extends)
- ✅ Stage references
- ✅ Needs dependencies (circular dependency detection)
- ✅ Extends references
- ✅ include, !reference, default:/inherit:, parallel/matrix (resolved as GitLab does)
- ⚠️  Non-standard keywords (warnings)


### DAG Command

Generate Graphviz DOT representation of pipeline DAG:

```bash
# Output DOT format to stdout
gitlab_ci_cli dag --entry .gitlab-ci.yml

# Generate PNG image
gitlab_ci_cli dag --entry .gitlab-ci.yml | dot -Tpng -o pipeline.png

# Generate SVG image
gitlab_ci_cli dag --entry .gitlab-ci.yml | dot -Tsvg -o pipeline.svg
```

The DAG visualization shows:
- Job grouping by stages
- Dependencies defined via `needs` keyword
- Execution order and parallelism opportunities

### Dry-Run Command

Simulate pipeline execution against mock runner fleet:

```bash
# Basic dry-run
gitlab_ci_cli dry-run --entry .gitlab-ci.yml --runners ./runners/

# With custom variables
gitlab_ci_cli dry-run --entry .gitlab-ci.yml \
  --variables ENVIRONMENT=staging \
  --variables DEPLOY_TOKEN=$TOKEN

# Simulate specific git reference
gitlab_ci_cli dry-run --entry .gitlab-ci.yml --ref feature/my-branch

# A tag pipeline, and an MR pipeline from feature/my-branch into the default branch
gitlab_ci_cli dag --ref refs/tags/v1.2.0
gitlab_ci_cli dag --pipeline merge_request_event --ref feature/my-branch
```

**Example output** (`examples/quickstart`, `--ref main`):
```
Pipeline #1 created with 5 job(s)

[T+0s] Job 'build' → Runner 'runner_001'
[T+0s] Job 'lint-docs' → Runner 'runner_001'
[T+5s] Job 'build' completed
[T+5s] Job 'lint-docs' completed
[T+6s] Job 'test: [linux]' → Runner 'runner_001'
[T+6s] Job 'test: [macos]' → Runner 'runner_001'
...
Simulation completed at T+18s

Pipeline status: success
```

A pipeline that cannot finish (no runner has a job's tags) stops as soon as
such a job is next to run, names the reason per job and exits 1.

## Predefined variables

Rules (`workflow:`, `include:` and job `rules:`) see GitLab's predefined
variables for the simulated pipeline, derived from `--pipeline`, `--ref` and
the git checkout (`lib/predefined_variables.rb` lists every variable and why).
As in GitLab, a variable that does not apply is **unset**, not empty:
`CI_COMMIT_BRANCH` exists only in branch pipelines (not in tag or MR
pipelines), `CI_COMMIT_TAG` only in tag pipelines, `CI_MERGE_REQUEST_*` only
in `merge_request_event` pipelines. The standard MR rules
(`$CI_PIPELINE_SOURCE == "merge_request_event"`, `$CI_MERGE_REQUEST_IID`,
`$CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS`) therefore evaluate as GitLab
does.

What cannot be known locally is left unset rather than invented, e.g.
`CI_COMMIT_REF_PROTECTED`, `CI_SERVER_*`, `CI_PROJECT_ID`,
`CI_OPEN_MERGE_REQUESTS`. Set them with `--variables` to simulate them
(`--variables CI_OPEN_MERGE_REQUESTS=group/proj!12` simulates a branch with an
open MR). Exceptions, so MR rules work:

- `CI_MERGE_REQUEST_IID` is a placeholder `1` (override with `--variables`).
- `CI_MERGE_REQUEST_TARGET_BRANCH_NAME` is the default branch.
- `CI_DEFAULT_BRANCH` comes from `origin/HEAD`, else `main`.
- `CI_PROJECT_PATH` is `namespace/name` from the `origin` remote URL; without
  a usable `origin` it falls back to the project directory's name (and the
  `CI_PROJECT_NAMESPACE*` variables are unset). A URL whose path is not a
  plausible GitLab path (e.g. `https://u:p/w@host/g/n`, a password with an
  unencoded `/`) also falls back: credentials in the URL never reach a
  variable.

`--pipeline` takes upstream source names (`push`, `web`, `schedule`, `api`,
`trigger`, `merge_request_event`, ...). The older names `merge_request` and
`manual` still work as aliases for `merge_request_event` and `web`.


## Includes

`include: local` reads from `--project`. The other kinds may need the
network (`https://` only, certificates verified; see
[SECURITY.md](../SECURITY.md#network)):

- `remote`: fetched from the URL. A host that resolves to any non-public
  address (loopback, private, link-local, IPv6 ULA, ...) is refused.
  `GITLAB_CI_ALLOWED_DOMAINS=host1,host2` restricts the allowed hosts.
- `project`: a checkout next to the project, `../<project>/<file>`, is read
  if it exists (its working tree: `ref:` is not honoured, and a warning
  says so). Otherwise the file is fetched from the one GitLab instance the
  pipeline runs on: `--variables CI_SERVER_URL=https://gitlab.example.com`
  if given, else the host of the `origin` remote, else gitlab.com. No other
  host is asked. For a repository whose `origin` is not on GitLab (say a
  GitHub mirror), pass `CI_SERVER_URL`.
- `component`: fetched from the host in the reference
  (`gitlab.com/group/project/name@1.0`).
- `template`: read from `--gitlab-dir`, else fetched from gitlab.com.

Downloads are cached in `ext_tmp/` in the current directory.

## Parallel jobs

`parallel: N` and `parallel:matrix` expand as GitLab does, before rules, so
every command sees the instances under GitLab's names: `rspec 1/3` ..
`rspec 3/3`, and `build: [aws, x86]` (matrix values in key order, one matrix
entry after another). Each instance gets its matrix variables as job
variables (`rules:variables` and `--variables` still win), `CI_NODE_INDEX`
(1-based) and `CI_NODE_TOTAL`; every other job gets `CI_NODE_TOTAL=1`.
`needs:`/`dependencies:` on a parallel job mean all its instances;
`needs:parallel:matrix` picks instances, also with `$[[ matrix.X ]]`.

## Running jobs: run and export-just

`run <job>` and `export-just` give a job these variables too, plus the
top-level, `workflow:rules:variables`, job, `rules:variables` and
`--variables` ones, in GitLab's precedence and expanded as GitLab and the
runner do (`lib/job_environment.rb`). Like a shell-executor runner, `run`
executes before_script + script in one `bash` with errexit and pipefail in the
project directory, then after_script in a second `bash` (also after a failure,
with `CI_JOB_STATUS`, 5 min limit or `RUNNER_AFTER_SCRIPT_TIMEOUT`), and exits
with the job's exit code (0 for an allowed failure). It runs on this host: no
image, services, cache or artifacts. `--run-deps incl` first runs the jobs the
target waits for, scheduled as dry-run schedules them. `export-just` writes
one shebang recipe per job doing the same; its variables are a snapshot taken
at export time.

Of the host environment a job sees only a base a shell needs: `PATH`, `HOME`,
`USER`, `LOGNAME`, `SHELL`, `LANG`, `LC_*`, `TERM`, `TZ`, `TMPDIR`
(`lib/host_environment.rb`). `--pass-env` changes that:

| `--pass-env` | The job also sees |
|---|---|
| `none` (default) | nothing more |
| `NAME[,NAME...]`, e.g. `AWS_PROFILE,SSH_AUTH_SOCK` | those, when set |
| `all` | the whole environment (the behaviour before this flag) |

In every mode the job's own variables win over a host variable of the same
name, and `--variables` win over both. GitLab's shell executor passes the
runner's whole environment through, the docker executor none; the default
here isolates, so a run on a laptop or inside a real CI job does not pick up
the host's `CI_*` values (`CI_JOB_ID`, `CI_COMMIT_TAG`, ...). An exported
recipe reads the names from the environment `just` runs in, when it runs,
and starts both shells from `env -i` with them (plain `env` under `all`).
The mode itself is written into the justfile at export time: regenerate to
change it.

`run` takes one instance by its full name, quoted:
`gitlab_ci_cli run 'build: [aws, x86]'`. The base name (`run build`) is
refused with the list of instances; it never runs them all.

`export-just` recipe names are just identifiers: each run of characters
other than letters, digits, `_` and `-` becomes one `_`, a trailing one is
dropped (`rspec 1/3` -> `rspec_1_3`, `build: [aws, x86]` -> `build_aws_x86`).
If two or more jobs map to the same name, every one of them gets `_` and the
first 6 hex digits of the SHA-256 of its own job name (`a b` -> `a_b_c8687a`,
`a/b` -> `a_b_c14cdd`); none keeps the bare `a_b`. A recipe name therefore
never depends on the order of jobs in the config, and a suffixed name always
runs the same job. Names that do not collide are unchanged. The comment above
each recipe keeps the job's real name. Config text (job names, stages, tags,
paths) only ever lands in the justfile as an identifier, as escaped comment
text, or inside the quoted recipe body, so it cannot add recipes or
assignments.


## CLI reference

`gitlab_ci_cli --help`:

```
gitlab_ci_cli - Local GitLab CI Pipeline Simulator

USAGE:
    gitlab_ci_cli [OPTIONS] [COMMAND] [ARGS]

COMMANDS:
    lint              Validate .gitlab-ci.yml syntax and semantics
    dag               Generate Graphviz DOT of pipeline DAG
    dry-run           Simulate pipeline execution against mock fleet
    run <job_name>    Execute a job locally (assumes tags/conditions match)
    export-just       Export jobs as justfile recipes
    help              Show this help message

OPTIONS:
    --entry FILE      Path to CI config (default: ./.gitlab-ci.yml)
    --project DIR     Project root: include:local, exists:/changes:, CI_PROJECT_DIR
                      (default: directory of --entry; upstream uses the
                      repository root, so pass --project when the entry
                      file is not at the root)
    --runners DIR     Runner fleet directory (default: ./runners)
    --ref REF         Ref the pipeline runs for: BRANCH, TAG, refs/heads/BRANCH or
                      refs/tags/TAG. A plain name is a tag if this repository has
                      that tag, otherwise a branch (may not exist yet). The commit
                      is always the checkout's HEAD. Default: the checked-out branch;
                      on a detached HEAD the one tag at HEAD; otherwise no ref
                      (CI_COMMIT_BRANCH/TAG/REF_NAME unset)
    --pipeline TYPE   CI_PIPELINE_SOURCE, an upstream source: push, web, schedule,
                      api, trigger, merge_request_event, parent_pipeline, ...
                      (default: push). Aliases: merge_request = merge_request_event,
                      manual = web. merge_request_event simulates a detached MR
                      pipeline from --ref into the default branch; its IID is a
                      placeholder (1), override with --variables
    --variables K=V   Set CI variables (can be repeated)
    --env K=V         Set environment variables (alias for --variables)
    --undefined MODE  Handle undefined vars: warning|error|empty (default: warning)
    --verbose         Increase output verbosity
    --format FORMAT   Output format: text|json|junit (default: text)
    --gitlab-dir DIR  GitLab checkout, read only by include:template (default: ./gitlab)
    --run-deps MODE   For 'run': incl (also the jobs it waits for, scheduled as in
                      dry-run) | excl (only the job) (default: excl)
    --pass-env MODE   For 'run' and 'export-just': which host environment variables
                      the job sees, under its own variables. none (default): only
                      PATH HOME USER LOGNAME SHELL LANG LC_* TERM TZ TMPDIR;
                      all: everything, like a GitLab shell executor (and this
                      tool before); NAME[,NAME...]: those as well. export-just
                      writes the mode into the recipes
    --output FILE     Output file for export-just (default: stdout)
    -o FILE           Alias for --output
    --flat            Export flat justfile (no dependencies)
    --graph           Export with dependency graph (default)
    --help, -h        Show this help message
    --version, -v     Show version information

EXAMPLES:
    gitlab_ci_cli lint
    gitlab_ci_cli dag | dot -Tpng -o pipeline.png
    gitlab_ci_cli dry-run --variables DEPLOY_ENV=staging
    gitlab_ci_cli run build-backend
    gitlab_ci_cli run test-unit --run-deps=incl
    gitlab_ci_cli export-just --flat -o justfile.gitlab.flat
    gitlab_ci_cli export-just --graph -o justfile.gitlab.graph
    gitlab_ci_cli lint --entry custom-ci.yml --verbose

VERSION:
    0.1.0
```

## Troubleshooting

### Common Issues

**Issue: Command not found**
```bash
# Solution: enter the dev shell, or use the packaged binary
nix develop        # then ./bin/gitlab_ci_cli
nix run . -- --help
```

**Issue: YAML syntax error**
```
Error: YAML syntax error: mapping values are not allowed...
```
Check your YAML for unquoted strings with special characters.

**Issue: Circular dependency detected**
```
Error: Circular dependency detected involving job 'test'
```
`lint` names one job of the cycle (`dag` refuses to draw a cyclic graph);
follow that job's `needs:` to find the loop:
```bash
gitlab_ci_cli lint --entry .gitlab-ci.yml
```

**Issue: chosen stage does not exist**
```
deploy job: chosen stage production does not exist; available stages are .pre, build, test, deploy, .post
```
Add the stage to your `stages:` list or remove the invalid stage reference.
`.pre` and `.post` never need declaring: they are always the first and last
stage. A pipeline whose jobs are all in `.pre`/`.post` (after rules) is not
created, as upstream.

