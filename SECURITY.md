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

- `include: remote`: every address the host resolves to must be public,
  else the include is refused: loopback, private, shared (100.64.0.0/10),
  link-local (including the cloud metadata address 169.254.169.254),
  multicast and reserved IPv4 ranges, and IPv6 `::1`, `::`, `fc00::/7`,
  `fe80::/10`, multicast and documentation ranges. An IPv6 address that
  embeds an IPv4 one (`::ffff:a.b.c.d`, NAT64 `64:ff9b::a.b.c.d`) is
  checked by that IPv4 address. A literal IP host is checked the same way;
  a host with no address is an error. The tool then connects to the
  address it checked (the certificate is still verified against the host
  name), so a DNS answer that changes after the check is not used.
  `GITLAB_CI_ALLOWED_DOMAINS=host1,host2` restricts remote includes to those
  hosts. The fetch times out after 3 s (connect) / 5 s (read). With an
  `https_proxy` set, the proxy makes the connection, to the checked address.
- `project`: read from `../<project>/<file>` next to the project directory
  if that exists (`ref` is then not honoured, and a warning says so);
  otherwise requested from one GitLab instance only, and no other host:
  `--variables CI_SERVER_URL` if set, else the host of the `origin` remote
  (as `https://`; credentials in the remote URL are not used), else
  gitlab.com. A failed fetch names that instance.
- `component`: fetched from the host named in the component reference.
  `template`: read from the `gitlab/` checkout, else fetched from
  gitlab.com (templates are public).
- `project`, `component` and `template` fetches time out after 10 s and are
  cached in `ext_tmp/` in the working directory, `project` files per
  instance.

YAML is loaded with a safe loader (no arbitrary Ruby objects), and include
nesting stops at 150 levels. There is no telemetry.
