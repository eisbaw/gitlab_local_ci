# Development

```bash
nix develop          # Ruby 3.3, graphviz, just
just setup           # once: the gitlab/ submodule (reference source) + dev gems
just test            # rspec, with the coverage ratchet
just e2e             # golden outputs of test_ci_projects/
```

## Gates

- **`just test`**: the rspec suite. It also measures coverage of the CLI
  processes the specs spawn, and fails below the ratchet in
  `spec/spec_helper.rb` (it only goes up). `just test-file FILE` runs one
  file; a subset alone never reaches the ratchet, so read its example count,
  not its exit code.
- **`just e2e`**: runs lint (text, json, junit), dag and dry-run on every
  `test_ci_projects/projN` and diffs stdout, stderr and exit codes against
  `projN.output_reference/`. After an intended behaviour change:
  `just e2e-update`, then review `git diff test_ci_projects/` and explain
  every golden change in the commit message. See
  [test_ci_projects/TESTING.md](../test_ci_projects/TESTING.md).
- Specs that evaluate rules pin the pipeline context
  (`spec/support/pinned_pipeline_context.rb`, `--ref refs/heads/main`), so
  the suite passes on any branch or detached checkout. Check it off `main`
  too.

## Upstream reference

`gitlab/` is a submodule of GitLab, pinned to a release tag (v19.5.3-ee).
Behaviour is ported from its source, not guessed, and some specs read it
(keyword lists, predefined variables). `include: template:` reads templates
from it at run time.

The 11 real-world projects under `external_projects/` are separate
submodules, a corpus for manual checks, fetched only on request
(`git submodule update --init external_projects`).

## Other recipes

From `just --list`:

```bash
just lint [FILE]          # lint a config (default test_ci_projects/proj1)
just dag [FILE] [OUTPUT]  # render the DAG to a PNG
just dry-run [FILE]       # simulate a config
just test-integration     # spec/integration only
just test-projN           # lint, dag and dry-run one test project
just clean                # remove generated PNGs and tmp/
```

Tasks live in `backlog/` and are managed with the
[backlog.md](https://github.com/MrLesk/Backlog.md) CLI (`backlog task list --plain`).
