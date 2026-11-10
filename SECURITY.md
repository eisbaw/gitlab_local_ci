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
- **Variables:** jobs started by `run` or an exported recipe see only a
  small base of the host environment (`PATH`, `HOME`, `USER`, `LOGNAME`,
  `SHELL`, `LANG`, `LC_*`, `TERM`, `TZ`, `TMPDIR`), so host `CI_*` values
  and tokens in your shell do not reach them. `--pass-env NAME,...` adds
  names; `--pass-env all` passes everything, including `CI_*` values that
  can shadow the simulated ones.
  `CI_PROJECT_PATH` is derived from the `origin` remote; credentials in that
  URL never reach a variable.

## Network

The tool makes no connection except to fetch an include that is not on disk:
`include: remote`, `project`, `component`, or a `template` missing from the
`gitlab/` checkout. All of them use `https://` only, with certificate
verification.

- `include: remote`: hosts whose first resolved address is an IPv4 loopback
  or private address are refused. IPv6 is not checked, so a name that
  resolves to `::1` first (such as `localhost`) gets through, and a DNS
  rebinding between the check and the request is not prevented.
  `GITLAB_CI_ALLOWED_DOMAINS=host1,host2` restricts remote includes to those
  hosts. The fetch times out after 3 s (connect) / 5 s (read).
- `project`: read from `../<project>/<file>` next to the project directory
  if that exists (`ref` is then ignored); otherwise requested from
  gitlab.com, gitlab.gnome.org and gitlab.freedesktop.org in turn, so the
  project path is sent to all three until one has it.
- `component`: fetched from the component's host. `template`: read from the
  `gitlab/` checkout, else fetched from gitlab.com.
- `project`, `component` and `template` fetches time out after 10 s and are
  cached in `ext_tmp/` in the working directory.

YAML is loaded with a safe loader (no arbitrary Ruby objects), and include
nesting stops at 150 levels. There is no telemetry.
