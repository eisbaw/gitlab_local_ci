# Security

## Supported versions

gitlab_ci_cli is 0.x. Only the latest `main` gets fixes; there are no release
branches.

## Reporting a vulnerability

Please do not open a public issue. Contact the maintainer,
[@eisbaw](https://github.com/eisbaw), privately through the contact details
on their GitHub profile, with a description, the impact, and a config or
steps that reproduce it.

## What the tool does with a config

- **`lint`, `dag`, `dry-run`** read the config and never execute its scripts.
- **`run`** executes the job's `before_script`, `script` and `after_script`
  with `bash` on this host, as your user, in the project directory. There is
  no container. Run only configs you trust.
- **`export-just`** writes a justfile whose recipes do the same when you
  invoke them. Text from the config (job names, stages, tags, paths) lands in
  the justfile only as an identifier, as escaped comment text or inside the
  quoted recipe body, so it cannot add recipes or assignments.
- **Variables:** host environment variables reach jobs started by `run`
  (including `CI_*` ones, which can shadow the simulated values).
  `CI_PROJECT_PATH` is derived from the `origin` remote; credentials in that
  URL never reach a variable.

## Network

The tool makes no connection except to fetch an include that is not on disk:
`include: remote`, `project`, `component`, or a `template` missing from the
`gitlab/` checkout. All of them use `https://` only, with certificate
verification.

- `include: remote`: hosts that resolve to loopback or private addresses are
  refused (a DNS rebinding between the check and the request is not
  prevented), `GITLAB_CI_ALLOWED_DOMAINS=host1,host2` restricts them to those
  hosts, and the fetch times out after 3 s (connect) / 5 s (read).
- `project`, `component`, `template`: fetched from the GitLab host
  (gitlab.com, or the component's host) with a 10 s timeout, and cached in
  `ext_tmp/` in the working directory.

YAML is loaded with a safe loader (no arbitrary Ruby objects), and include
nesting stops at 150 levels. There is no telemetry.
