# Security Policy

## Supported Versions

This section describes which versions of `gitlab_ci_cli` receive security updates.

| Version | Supported          | Status |
| ------- | ------------------ | ------ |
| main    | :white_check_mark: | Active development branch |
| 1.x     | :white_check_mark: | Current stable release |
| < 1.0   | :x:                | Pre-release, not supported |

**Version Support Timeline:**
- **Current stable version (1.x)**: Receives all security updates and patches
- **Development branch (main)**: Latest features and security fixes
- **Pre-release versions**: No security support provided

We recommend always using the latest stable release for production use.

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue in `gitlab_ci_cli`, please report it responsibly.

### How to Report

**DO NOT** open a public issue for security vulnerabilities.

Instead, please report security issues through one of the following channels:

1. **Preferred**: Email security concerns to the maintainer(s)
2. **Alternative**: Open a draft security advisory on GitHub (if available)
3. **Private disclosure**: Contact maintainers directly via secure channels

### What to Include

When reporting a vulnerability, please include:

- **Description**: Clear description of the vulnerability
- **Impact**: What could an attacker accomplish?
- **Reproduction steps**: Step-by-step instructions to reproduce the issue
- **Affected versions**: Which versions are vulnerable?
- **Proof of concept**: Example code/config demonstrating the issue (if applicable)
- **Suggested fix**: If you have recommendations for remediation

### Response Timeline

- **Initial response**: Within 72 hours of report
- **Triage assessment**: Within 1 week
- **Fix development**: Depends on severity (critical issues prioritized)
- **Public disclosure**: After fix is available, coordinated with reporter

### Disclosure Policy

We follow **coordinated disclosure**:

1. You report the vulnerability privately
2. We confirm the issue and develop a fix
3. We release a security update
4. We publicly disclose the vulnerability (typically 7-14 days after fix release)
5. Credit is given to the reporter (unless anonymity is requested)

We appreciate security researchers who follow responsible disclosure practices.

## Security Considerations

### Known Limitations

#### DNS Rebinding Vulnerability in SSRF Protection

The `IncludeProcessor` validates remote URLs to prevent Server-Side Request Forgery (SSRF) attacks by blocking private IP addresses. However, this protection has a known limitation:

**Limitation**: DNS rebinding attacks are possible. A hostname may initially resolve to a public IP address (passing validation), but subsequently resolve to a private IP when the actual HTTP request is made.

**Root cause**: Ruby's `Net::HTTP` library does not provide hooks to validate resolved IP addresses at connection time. The validation happens before DNS resolution occurs for the HTTP request.

**Impact**: An attacker controlling DNS could potentially bypass SSRF protection to access internal services.

**Mitigation options**:
- Set `GITLAB_CI_ALLOWED_DOMAINS` environment variable to restrict remote includes to a trusted allowlist
- Use local includes (`local:`) instead of remote includes when possible
- Review and audit all remote include URLs in CI configurations
- Deploy network-level protections (firewall rules, network segmentation)

**Future work**: We are investigating alternative HTTP clients or DNS resolution strategies that would allow validation at connection time.

#### Template File Access

The `IncludeProcessor` can fetch GitLab CI templates from the filesystem when `gitlab_templates_path` is configured. This provides access to the GitLab template library but also means:

- Template path must be carefully controlled
- Path traversal is mitigated by using `File.join` with absolute base paths
- Only configured template directory is accessible

### Recommended Security Practices

#### 1. Use HTTPS for Remote Includes

Remote includes enforce HTTPS-only connections:
```yaml
include:
  - remote: 'https://example.com/ci-template.yml'  # OK
  - remote: 'http://example.com/ci-template.yml'   # Rejected
```

**Why**: Prevents man-in-the-middle attacks and ensures integrity of included configurations.

#### 2. Restrict Remote Domains

Set `GITLAB_CI_ALLOWED_DOMAINS` to limit remote includes:

```bash
export GITLAB_CI_ALLOWED_DOMAINS="gitlab.com,trusted-domain.example.com"
gitlab_ci_cli lint --entry .gitlab-ci.yml
```

**Why**: Reduces attack surface by limiting which external sources can be included.

#### 3. Prefer Local Includes

Use `local:` includes over `remote:` when possible:
```yaml
include:
  - local: 'templates/security-scanning.yml'  # Preferred
```

**Why**: Eliminates network-based attacks and ensures templates are version-controlled.

#### 4. Review Included Configurations

Audit all included YAML files, especially from external sources:
- Check for unexpected script commands
- Validate variable usage
- Review artifact collection patterns
- Verify image sources

**Why**: Included files execute with the same permissions as your main CI configuration.

#### 5. Limit Runner Fleet Exposure

Store runner configuration files securely:
```bash
chmod 600 runners/*.json
```

**Why**: Runner configurations may contain sensitive metadata about your infrastructure.

#### 6. Validate CI Configurations Before Commit

Use `gitlab_ci_cli lint` in pre-commit hooks:
```bash
# .git/hooks/pre-commit
#!/bin/bash
gitlab_ci_cli lint --entry .gitlab-ci.yml
```

**Why**: Catches configuration errors and potential security issues early.

## Security Features

### 1. Shell Injection Protection

**Protection**: `ChildPipelineHandler` uses `Open3.capture2e` with direct argument passing.

**Implementation**:
```ruby
# Secure: Arguments passed directly, no shell interpretation
output, status = Open3.capture2e(*args)
```

**What this prevents**:
- Command injection via crafted job names or variables
- Shell metacharacter exploitation
- Arbitrary command execution

**Example attack prevented**:
```yaml
# Malicious CI config attempting injection
variables:
  MALICIOUS: "; rm -rf / #"

# Our implementation safely passes this as a literal string, not executed
```

### 2. SSRF Protection

**Protection**: `IncludeProcessor` blocks remote includes to private IP addresses.

**Blocked IP ranges**:
- Loopback: `127.0.0.0/8`
- Private Class A: `10.0.0.0/8`
- Private Class B: `172.16.0.0/12`
- Private Class C: `192.168.0.0/16`
- Link-local: `169.254.0.0/16`
- Multicast: `224.0.0.0/4`
- Broadcast: `255.255.255.255`
- Unspecified: `0.0.0.0`

**Implementation**:
```ruby
def validate_not_private_ip(hostname)
  ip = Resolv.getaddress(hostname)
  raise "Private IP detected" if ip.start_with?('127.', '10.', '192.168.')
  # ... additional checks
end
```

**What this prevents**:
- Access to internal services (databases, admin panels, metadata APIs)
- Port scanning of internal network
- Reading local files via file:// protocol (blocked by HTTPS-only requirement)

**Known limitation**: See "DNS Rebinding Vulnerability" above.

### 3. HTTPS Enforcement

**Protection**: Remote includes require HTTPS protocol.

**Implementation**:
```ruby
unless uri.scheme == 'https'
  raise "Remote includes must use HTTPS for security"
end
```

**What this prevents**:
- Man-in-the-middle attacks
- Configuration tampering in transit
- Credential exposure

### 4. Input Validation

**Protection**: Validates CLI arguments, YAML structure, and runner configurations.

**Validation points**:
- YAML parsing with safe_load and restricted classes
- File path validation (existence checks, no path traversal)
- URL validation (scheme, host, format)
- Circular include detection
- Include depth limiting (max 150 levels)

**What this prevents**:
- YAML deserialization attacks
- Path traversal attacks
- Infinite recursion / resource exhaustion
- Circular dependency deadlocks

### 5. Timeout Protection

**Protection**: Network requests have timeouts to prevent resource exhaustion.

**Implementation**:
```ruby
Net::HTTP.start(
  uri.host, uri.port,
  use_ssl: true,
  read_timeout: 5,      # 5 second read timeout
  open_timeout: 3,      # 3 second connection timeout
  verify_mode: OpenSSL::SSL::VERIFY_PEER
)
```

**What this prevents**:
- Slowloris-style attacks
- Resource exhaustion from hanging connections
- Denial of service via slow responses

### 6. SSL Certificate Verification

**Protection**: SSL certificates are verified for all HTTPS connections.

**Implementation**:
```ruby
verify_mode: OpenSSL::SSL::VERIFY_PEER
```

**What this prevents**:
- Man-in-the-middle attacks
- Impersonation attacks
- Credential interception

### 7. Include Depth Limiting

**Protection**: Maximum include depth of 150 levels (matches GitLab's limit).

**Implementation**:
```ruby
MAX_DEPTH = 150
raise IncludeDepthExceededError if depth > MAX_DEPTH
```

**What this prevents**:
- Stack overflow from infinite recursion
- Resource exhaustion
- Denial of service attacks

### 8. Circular Include Detection

**Protection**: Tracks processed includes to prevent circular references.

**Implementation**:
```ruby
@processed_includes = Set.new
raise "Circular include detected" if @processed_includes.include?(identifier)
```

**What this prevents**:
- Infinite loops
- Resource exhaustion
- Denial of service

## Threat Model

### What This Tool Protects Against

#### Local Development Threats

- **Malicious included configurations**: SSRF protection and HTTPS enforcement reduce risk of fetching malicious configs
- **Command injection**: Direct argument passing prevents shell injection
- **Resource exhaustion**: Timeouts, depth limits, and circular detection prevent DoS
- **Path traversal**: Input validation prevents access to arbitrary files

#### Supply Chain Threats

- **Compromised remote includes**: HTTPS enforcement and SSL verification protect integrity
- **DNS attacks**: Domain allowlist reduces attack surface (though DNS rebinding remains possible)
- **Template tampering**: Local templates are version-controlled and auditable

### What This Tool Does NOT Protect Against

#### Out of Scope Threats

1. **Malicious CI scripts**: This tool simulates pipeline execution but does not sandbox or restrict script commands. If a CI configuration contains malicious scripts, this tool will show what would be executed but provides no runtime protection.

2. **Host system compromise**: If the system running `gitlab_ci_cli` is compromised, all protections can be bypassed.

3. **Credential exposure in configs**: This tool does not scan for or redact secrets in YAML files. Users must manage secrets appropriately.

4. **GitLab submodule vulnerabilities**: The tool uses GitLab source code as a submodule. Vulnerabilities in GitLab itself may affect this tool.

5. **Ruby interpreter vulnerabilities**: Security depends on the Ruby interpreter and standard library.

6. **DNS rebinding attacks**: See "Known Limitations" above.

7. **Time-of-check-time-of-use (TOCTOU)**: File system checks are not atomic. Files could change between validation and use.

8. **Social engineering**: No technical control prevents users from manually adding malicious configurations.

### Trust Boundaries

This tool operates within the following trust boundaries:

```
┌─────────────────────────────────────────────────────────┐
│                      Trusted Zone                        │
│                                                          │
│  ┌──────────────┐         ┌─────────────┐              │
│  │  User Input  │────────▶│ gitlab_ci   │              │
│  │ (.gitlab-ci) │         │    _cli     │              │
│  └──────────────┘         └─────────────┘              │
│                                  │                       │
│  ┌──────────────┐                │                       │
│  │   Runners/   │◀───────────────┘                       │
│  │  (local JSON)│                                        │
│  └──────────────┘                                        │
│                                                          │
└─────────────────────────────────────────────────────────┘
                          │
                          │ HTTPS + SSRF Protection
                          ▼
┌─────────────────────────────────────────────────────────┐
│                    Untrusted Zone                        │
│                                                          │
│    • Remote include sources (external URLs)             │
│    • DNS resolvers                                       │
│    • Network infrastructure                              │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

**Trusted**: Local filesystem, user-provided configurations, runner definitions
**Untrusted**: Remote URLs, network responses, DNS results

## Dependency Security

### Ruby Dependencies

This project minimizes dependencies to reduce attack surface:

**Core dependencies**:
- Ruby standard library (YAML, Net::HTTP, Open3, Resolv)
- Minimal external gems (see Gemfile)

**Security practices**:
- Dependencies are managed via Bundler with Gemfile.lock
- Nix shell provides reproducible environment
- Regular dependency updates (monitor for CVEs)

### GitLab Submodule

The project includes GitLab as a git submodule for CI/CD logic reuse.

**Security considerations**:
- Submodule pinned to specific version (not floating)
- Zero-patch policy: No modifications to GitLab code
- Upstream security updates tracked
- Version compatibility tested

**Updating submodule**:
```bash
just update-gitlab  # Updates to latest stable version
```

## Security Update Process

When security vulnerabilities are discovered:

1. **Assessment**: Evaluate severity and impact
2. **Fix development**: Develop and test patch
3. **Release preparation**: Prepare security advisory
4. **Coordinated disclosure**: Notify affected users
5. **Public release**: Release fix with security advisory
6. **Postmortem**: Document lessons learned

## Security Best Practices for Contributors

If you're contributing to this project:

1. **Fail-fast validation**: Validate input early and loudly
2. **Avoid shell commands**: Use Ruby APIs directly (no system calls with user input)
3. **Validate file paths**: Use `File.expand_path` and check for path traversal
4. **Limit network access**: Validate URLs and implement timeouts
5. **Log security events**: Log authentication failures, blocked requests, validation errors
6. **Test edge cases**: Include security test cases for injection, traversal, SSRF
7. **Document security implications**: Note security trade-offs in code comments

## Additional Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [GitLab Security Best Practices](https://docs.gitlab.com/ee/security/)
- [Ruby Security Guide](https://www.rubysecurityguide.com/)
- [CONTRIBUTING.md](CONTRIBUTING.md) - Development guidelines
- [README.md](README.md) - Project documentation

## Contact

For security-related questions or concerns that are not vulnerabilities:
- Open a discussion on GitHub
- Review existing security issues
- Consult project documentation

For security vulnerabilities, follow the "Reporting a Vulnerability" process above.

---

**Last Updated**: 2025-10-14
**Version**: 1.0
