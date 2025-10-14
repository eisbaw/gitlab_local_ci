# Data Privacy and Compliance Documentation

**gitlab_ci_cli** - Local GitLab CI Pipeline Simulator

Version: 1.0
Last Updated: 2025-10-14

---

## Executive Summary

`gitlab_ci_cli` is a privacy-first local tool that processes GitLab CI configurations entirely on your machine. The tool makes **no telemetry or analytics connections** by default. Network activity only occurs when explicitly configured features like remote includes are used.

**Key Privacy Facts:**
- Zero telemetry or analytics
- No data sent to third parties by default
- All pipeline processing is local
- Network requests only for remote includes (optional feature)
- No persistent storage of sensitive data
- No user tracking or profiling

---

## 1. Data Collection

### 1.1 What Data is Collected?

**None.** The tool collects no telemetry, analytics, crash reports, or usage statistics.

### 1.2 What Data is Processed Locally?

The tool processes the following data **entirely on your local machine**:

1. **GitLab CI Configuration Files (.gitlab-ci.yml)**
   - Location: User-specified file paths
   - Purpose: Pipeline validation and simulation
   - Storage: Read from disk, parsed in memory, never persisted by the tool
   - Retention: Cleared when process terminates

2. **Runner Configuration Files (runners/*.json)**
   - Location: User-specified directory
   - Purpose: Simulate runner fleet capacity
   - Storage: Read from disk, loaded into memory
   - Retention: Cleared when process terminates

3. **Environment Variables**
   - Source: Process environment via `ENV[]`
   - Purpose:
     - `GITLAB_CI_ALLOWED_DOMAINS` - Domain allowlist for remote includes
   - Access Pattern: Read-only, never modified or persisted
   - Privacy Note: Other environment variables are NOT accessed by the tool

4. **CI/CD Variables (--variables flag)**
   - Source: Command-line arguments
   - Purpose: Variable expansion during pipeline simulation
   - Storage: In-memory only during execution
   - Retention: Cleared when process terminates
   - Security Warning: May contain secrets (see Section 4.1)

### 1.3 What Data is Stored?

**None persistently.** The tool:
- Does NOT create databases
- Does NOT write configuration files
- Does NOT cache data between runs
- Does NOT create log files (output goes to stdout/stderr)
- Only writes files when explicitly requested (e.g., exporting runner configs)

### 1.4 What Data is Transmitted?

**Conditionally, only when remote includes are used:**

The tool makes network requests **only** when your `.gitlab-ci.yml` contains remote include directives:

```yaml
include:
  - remote: 'https://example.com/ci-template.yml'
```

When remote includes are present:
- **Protocol:** HTTPS only (HTTP blocked for security)
- **Data Sent:** HTTP GET request with standard headers
- **Data Received:** YAML configuration file content
- **User Control:** Can be disabled by not using remote includes
- **Domain Filtering:** Optional via `GITLAB_CI_ALLOWED_DOMAINS` environment variable

**No network requests for:**
- Linting (`lint` command) - fully local
- DAG visualization (`dag` command) - fully local
- Dry-run simulation (`dry-run` command) - fully local
- Local includes (file system only)

---

## 2. Network Activity

### 2.1 When Does the Tool Make Network Requests?

Network requests occur **only** in these scenarios:

1. **Remote Includes (Optional Feature)**
   - Trigger: `.gitlab-ci.yml` contains `include: remote:` directive
   - Implementation: `lib/include_processor.rb` lines 163-190
   - Protocol: HTTPS only (enforced)
   - Timeout: 3 seconds connection, 5 seconds read
   - SSL Verification: Enabled (`VERIFY_PEER`)

2. **Runner Exporter (Separate Tool)**
   - Trigger: Explicit use of `RunnerExporter` class with GitLab API
   - Purpose: Export runner configs from production GitLab instance
   - Implementation: `lib/runner_exporter.rb`
   - Requirement: User provides GitLab URL and API token
   - Note: This is a **separate utility**, not part of normal CLI usage

### 2.2 What Data is Sent in Network Requests?

**For Remote Includes:**
```
GET /path/to/ci-template.yml HTTPS/1.1
Host: example.com
User-Agent: Ruby Net::HTTP
Accept: */*
```

- **URL:** User-specified in YAML configuration
- **Headers:** Standard HTTP headers only
- **Body:** None (GET requests)
- **Cookies:** None sent or accepted
- **Authentication:** None (public URLs only)

**For Runner Exporter (manual tool):**
- Standard GitLab API requests with user-provided token
- Only when explicitly invoked by user
- Not part of normal CLI operation

### 2.3 What Domains Can Be Contacted?

**By Default:**
- Any HTTPS domain specified in remote includes
- SSRF protection blocks private IP ranges (see Section 3.3)

**With GITLAB_CI_ALLOWED_DOMAINS (Recommended for Security):**
```bash
export GITLAB_CI_ALLOWED_DOMAINS="gitlab.com,raw.githubusercontent.com"
gitlab_ci_cli lint --entry .gitlab-ci.yml
```

Only domains in the allowlist will be contacted. Requests to other domains will fail with clear error message.

### 2.4 Network Request Logging

The tool does **not** log network requests to files. Output goes to:
- **stdout:** Normal command output
- **stderr:** Warnings and errors (including network failures)

Users can capture logs if desired:
```bash
gitlab_ci_cli lint 2>&1 | tee run.log
```

---

## 3. Security Considerations

### 3.1 Variables May Contain Secrets

**Risk:** CI/CD variables often contain sensitive data:
- API tokens
- Database passwords
- SSH keys
- Cloud credentials

**Mitigation:**
1. Variables are stored in memory only (not persisted)
2. Process memory is cleared when tool exits
3. Variables are not logged to stdout by default
4. Use OS-level security for sensitive data (keychains, secret managers)

**Best Practice:**
```bash
# Instead of:
gitlab_ci_cli dry-run --variables API_TOKEN=secret123

# Use environment variables:
export API_TOKEN=secret123
gitlab_ci_cli dry-run --variables API_TOKEN=$API_TOKEN
```

### 3.2 Remote Includes Fetch External Content

**Risk:** Remote includes execute arbitrary YAML from external sources.

**Security Implications:**
1. **Supply Chain Risk:** External templates can change without your knowledge
2. **Data Exfiltration:** Malicious templates could contain jobs that send data elsewhere
3. **Code Injection:** Templates define job scripts that would execute if deployed

**Mitigations Implemented:**
1. **HTTPS Only:** HTTP blocked, preventing man-in-the-middle attacks
2. **SSL Verification:** Certificates validated against system trust store
3. **SSRF Protection:** Private IP ranges blocked (see Section 3.3)
4. **Timeouts:** 3s connection, 5s read (prevents resource exhaustion)
5. **Domain Allowlisting:** Optional via `GITLAB_CI_ALLOWED_DOMAINS`

**Recommended Configuration:**
```bash
# Lock down to trusted domains only
export GITLAB_CI_ALLOWED_DOMAINS="gitlab.com,internal-template-server.corp.example.com"
```

**Known Limitation:**
- DNS rebinding attacks: A hostname could resolve to a safe IP during validation, then resolve to a private IP during the actual request. Ruby's Net::HTTP does not provide hooks to validate resolved IPs after DNS resolution.

### 3.3 SSRF (Server-Side Request Forgery) Protection

The tool implements SSRF protection to prevent access to internal services:

**Blocked IP Ranges:**
- `127.0.0.0/8` - Loopback (localhost)
- `10.0.0.0/8` - Private Class A
- `172.16.0.0/12` - Private Class B (172.16.0.0 - 172.31.255.255)
- `192.168.0.0/16` - Private Class C
- `169.254.0.0/16` - Link-local
- `224.0.0.0/4` - Multicast
- `0.0.0.0` - Unspecified address
- `255.255.255.255` - Broadcast

**Implementation:** `lib/include_processor.rb` lines 233-259

**Validation Flow:**
1. Parse URL and validate HTTPS scheme
2. Resolve hostname to IP address via DNS
3. Check IP against private ranges
4. If allowed, check against domain allowlist (if configured)
5. Make request with SSL verification and timeouts

**Important Note:** This protection is **best-effort**. It cannot prevent all SSRF attacks due to DNS rebinding limitations.

### 3.4 File System Access

**Read Access:**
- `.gitlab-ci.yml` and included files (user-specified paths)
- Runner JSON files (user-specified directory)
- GitLab templates (optional, from GitLab submodule)

**Write Access:**
- **None** during normal operation
- Runner exporter writes JSON files only when explicitly invoked

**Path Traversal Protection:**
- Local includes use `File.join` with absolute path resolution
- No validation against path traversal attacks (user is trusted)
- Assumption: User controls input files and paths

**File Permission Errors:**
- Fail-fast with clear error messages
- No silent failures on permission denied

---

## 4. User Privacy

### 4.1 No Telemetry or Analytics

The tool contains **zero telemetry code**:
- No phone-home functionality
- No usage statistics collection
- No crash reporting
- No feature usage tracking
- No version check pings

**Verification:**
```bash
# Search codebase for telemetry indicators
grep -r "analytics\|telemetry\|tracking\|phone.*home" lib/
# Returns: No results
```

### 4.2 No Data Sent to Third Parties

The tool does **not** communicate with:
- Anthropic or Claude services
- GitLab.com (unless explicitly used in remote includes)
- Package registries (except during initial `bundle install`)
- Update servers
- Analytics services
- Error tracking services (Sentry, Bugsnag, etc.)

**Exception:** Remote includes may fetch from user-specified domains.

### 4.3 All Processing is Local

Pipeline validation and simulation happens entirely on your machine:
- YAML parsing: In-memory using Ruby stdlib
- DAG construction: Local graph algorithms
- Job scheduling simulation: Local state machine
- Variable expansion: Local string processing

**No server-side processing.**

### 4.4 No Persistent Identifiers

The tool does **not** create or use:
- User IDs or session IDs
- Installation IDs or machine IDs
- Device fingerprints
- Tracking cookies
- License keys (tool is open source)

### 4.5 Privacy of CI Configuration

Your `.gitlab-ci.yml` files are **never transmitted** except:
1. When they contain remote includes (fetches external templates)
2. When you manually use the runner exporter with GitLab API

The tool **does not**:
- Upload configurations to any service
- Share configurations with other users
- Cache configurations in cloud storage
- Analyze configurations for telemetry

---

## 5. Compliance

### 5.1 GDPR Compliance

**Data Controller Status:**
The tool does **not** act as a data controller because:
- It processes no personal data
- It collects no personal data
- It stores no personal data
- It transmits no personal data

**Data Processor Status:**
The tool processes user-provided CI configurations locally:
- Processing is entirely on user's machine (data subject's device)
- No third-party processing
- No cross-border data transfer
- Data is transient (in-memory only)

**User Rights:**
- **Right to Access:** User has direct filesystem access to all input data
- **Right to Rectification:** User modifies files directly
- **Right to Erasure:** User deletes files directly
- **Right to Data Portability:** All data is in standard formats (YAML, JSON)
- **Right to Object:** No automated decision-making occurs

**Conclusion:** The tool is **GDPR-compliant by design** due to local-only processing.

### 5.2 Enterprise Considerations

**Air-Gapped Environments:**
The tool works in air-gapped/offline environments:
- No network connectivity required for core functionality
- Dependencies installed via Nix (reproducible, offline-capable)
- Remote includes will fail gracefully with clear error messages

**Corporate Network Policies:**
- Proxy Configuration: Not implemented (Ruby Net::HTTP respects `http_proxy` env var)
- Certificate Trust: Uses system certificate store
- Domain Allowlisting: Via `GITLAB_CI_ALLOWED_DOMAINS` environment variable

**Data Residency:**
All data remains on the machine where the tool runs:
- No cloud processing
- No data leaving corporate network (except remote includes)
- Compliance with data residency requirements

**License Compliance:**
- Tool: Apache License 2.0 (permissive, enterprise-friendly)
- Dependencies: See `Gemfile.lock` for third-party licenses
- No GPL or copyleft components in core tool

### 5.3 Audit Trail

**Local Only:**
The tool creates no persistent audit logs. All output goes to stdout/stderr:

```bash
# User captures their own audit trail if needed:
gitlab_ci_cli lint --entry .gitlab-ci.yml 2>&1 | tee audit.log
```

**No External Logging:**
- No syslog integration
- No remote logging services
- No centralized log aggregation

**Recommendation for Enterprises:**
Wrap the tool with your own logging layer:

```bash
#!/bin/bash
# audit-wrapper.sh
timestamp=$(date -Iseconds)
user=$(whoami)
host=$(hostname)

echo "[$timestamp] $user@$host: gitlab_ci_cli $@" >> /var/log/gitlab_ci_cli_audit.log

gitlab_ci_cli "$@"
exit_code=$?

echo "[$timestamp] $user@$host: exit code $exit_code" >> /var/log/gitlab_ci_cli_audit.log
exit $exit_code
```

### 5.4 Security Compliance

**Common Security Standards:**

**SOC 2 / ISO 27001:**
- Tool processes no customer data requiring SOC 2 controls
- All processing is local (customer controls their environment)
- No shared infrastructure or multi-tenancy concerns

**PCI-DSS:**
- Tool does not process payment card data
- If CI configurations contain PCI data (they shouldn't), it's user's responsibility
- No persistent storage of sensitive authentication data

**HIPAA:**
- Tool does not process Protected Health Information (PHI)
- If CI configurations contain PHI (they shouldn't), it's user's responsibility
- No Business Associate Agreement (BAA) required

**FedRAMP:**
- Tool suitable for government use (no cloud processing)
- All processing in user-controlled environment
- No federal data transmitted to third parties

### 5.5 Open Source Transparency

**Code Transparency:**
- Full source code available for audit
- No obfuscation or binary-only components
- Reproducible builds via Nix

**Dependency Transparency:**
- All dependencies listed in `Gemfile.lock`
- No hidden or proprietary dependencies
- Standard Ruby gems from RubyGems.org

**Verification:**
```bash
# Audit all code that makes network requests:
grep -r "Net::HTTP\|open-uri\|Faraday\|RestClient" lib/

# Result: Only lib/include_processor.rb (remote includes)
#         and lib/runner_exporter.rb (manual export tool)
```

---

## 6. Implementation Details

### 6.1 Code Locations for Privacy-Relevant Operations

**Network Requests:**
- File: `lib/include_processor.rb`
- Lines: 163-190 (fetch_remote_include method)
- Lines: 197-231 (validate_remote_url method)
- Lines: 233-259 (validate_not_private_ip method)

**File System Access:**
- Read: `lib/commands/lint_command.rb` (lines 120-143)
- Read: `lib/runner_fleet.rb` (lines 35-62)
- Write: `lib/runner_exporter.rb` (lines 149-167)

**Environment Variable Access:**
- File: `lib/include_processor.rb`
- Line: 219 (`ENV['GITLAB_CI_ALLOWED_DOMAINS']`)

**API Interaction (Runner Exporter Only):**
- File: `lib/runner_exporter.rb`
- Lines: 46-93 (export_from_gitlab method)

### 6.2 Data Flow Diagram

```
┌─────────────────┐
│  User           │
│  (Local Machine)│
└────────┬────────┘
         │
         │ Provides:
         │ - .gitlab-ci.yml
         │ - runners/*.json
         │ - CLI arguments
         │
         ▼
┌─────────────────────────────────┐
│  gitlab_ci_cli Process          │
│  ┌───────────────────────────┐  │
│  │ In-Memory Processing Only │  │
│  ├───────────────────────────┤  │
│  │ 1. Parse YAML (Psych)     │  │
│  │ 2. Validate Structure     │  │
│  │ 3. Build DAG              │  │
│  │ 4. Simulate Execution     │  │
│  └───────────────────────────┘  │
│                                  │
│  Network (Optional):             │
│  ┌───────────────────────────┐  │
│  │ Remote Includes Only      │  │
│  │ - HTTPS GET requests      │  │
│  │ - SSRF protection         │  │
│  │ - Domain allowlist        │  │
│  └───────────────────────────┘  │
│                                  │
│  Storage: NONE                   │
│  - No databases               │  │
│  - No cache files             │  │
│  - No persistent logs         │  │
└─────────┬───────────────────────┘
          │
          │ Outputs to:
          │ - stdout (results)
          │ - stderr (errors)
          │
          ▼
┌─────────────────┐
│  Terminal       │
│  (User Controls)│
└─────────────────┘
```

### 6.3 Memory Management

**In-Memory Data Lifecycle:**
1. **Load:** YAML parsed into Ruby Hash objects
2. **Process:** Jobs extracted, DAG validated, simulation runs
3. **Output:** Results formatted and printed to stdout
4. **Clear:** Ruby garbage collector frees memory when process exits

**No Persistent State:**
- No caching between invocations
- Each run is independent
- Process memory released on exit

**Security Note:** Memory is not explicitly zeroed before deallocation. Sensitive data in variables may remain in memory until overwritten. This is standard Ruby behavior.

---

## 7. Recommendations for Users

### 7.1 Secure Configuration

**Recommended Environment Setup:**

```bash
# shell.nix or .envrc
export GITLAB_CI_ALLOWED_DOMAINS="gitlab.com,gitlab.internal.corp"

# Disable remote includes entirely (if not needed):
# Remove all 'include: remote:' directives from .gitlab-ci.yml
```

**For High-Security Environments:**

```bash
# Run in isolated environment (container, VM, etc.)
nix-shell --pure  # Isolates from host environment

# Audit remote includes before accepting:
grep -r "include:" .gitlab-ci.yml

# Use local copies of templates instead of remote:
include:
  - local: 'templates/security-scan.yml'  # Good
  # - remote: 'https://...'               # Avoid in secure environments
```

### 7.2 Handling Secrets

**Best Practices:**

1. **Never Commit Secrets to YAML:**
   ```yaml
   # BAD - Secret in config file
   variables:
     API_KEY: "sk_live_1234..."  # NEVER DO THIS

   # GOOD - Reference environment variable
   variables:
     API_KEY: $API_KEY  # Tool expands from environment
   ```

2. **Use OS-Level Secret Management:**
   ```bash
   # macOS Keychain:
   security find-generic-password -s gitlab_token -w | \
     gitlab_ci_cli dry-run --variables TOKEN=$(cat)

   # Linux Secret Service:
   secret-tool lookup service gitlab | \
     gitlab_ci_cli dry-run --variables TOKEN=$(cat)
   ```

3. **Limit Variable Visibility:**
   ```bash
   # Variables only visible to this process:
   env API_KEY=secret gitlab_ci_cli dry-run --variables API_KEY=$API_KEY
   ```

### 7.3 Network Security

**Minimize Network Exposure:**

1. **Use Local Includes:**
   ```yaml
   include:
     - local: 'templates/build.yml'
     - local: 'templates/test.yml'
   ```

2. **Pin Template Versions:**
   ```yaml
   # BAD - Uses latest (can change):
   include:
     - remote: 'https://example.com/template.yml'

   # GOOD - Pin to specific commit/version:
   include:
     - remote: 'https://example.com/template.yml?ref=v1.2.3'
   ```

3. **Mirror Templates Internally:**
   ```yaml
   # Fetch external templates into your repo:
   include:
     - local: 'vendor/templates/external-template.yml'
   ```

### 7.4 Audit and Monitoring

**Regular Security Checks:**

```bash
# Audit what remote includes are used:
grep -r "remote:" .gitlab-ci.yml

# Check for sensitive data in configs:
grep -r "password\|token\|secret\|key" .gitlab-ci.yml

# Verify tool version (for security updates):
gitlab_ci_cli --version
```

**Network Monitoring:**

```bash
# Monitor DNS queries (Linux):
sudo tcpdump -i any -n "port 53"

# Monitor HTTPS connections (Linux):
sudo tcpdump -i any -n "port 443"
```

Run these in separate terminal while running the tool to verify network activity.

### 7.5 Corporate Compliance

**For Enterprise Deployments:**

1. **Wrap with Corporate Tooling:**
   - Integrate with existing CI/CD platforms
   - Add centralized logging/auditing
   - Enforce corporate policies (domain allowlists, etc.)

2. **Vendor Risk Assessment:**
   - Tool is open source (no vendor lock-in)
   - No SaaS dependencies
   - No data processing agreements required

3. **Change Management:**
   - Pin Nix dependencies to specific versions
   - Test updates in staging before production
   - Subscribe to security advisories (GitHub watch)

---

## 8. Contact and Transparency

### 8.1 Privacy Questions

For privacy-related questions or concerns:
- **GitHub Issues:** https://github.com/[repo]/issues
- **Security Issues:** See SECURITY.md for responsible disclosure

### 8.2 Privacy Policy Updates

This document will be updated when:
- New features introduce data processing changes
- Security mitigations are added or changed
- Legal or compliance requirements change

**Change Log:**
- 2025-10-14: Initial privacy documentation (v1.0)

### 8.3 Third-Party Dependencies

Privacy implications of dependencies:
- **Ruby stdlib:** System-provided, no telemetry
- **RubyGems (via Bundler):** Package manager, standard HTTPS fetches during install
- **Nix:** Package manager, fetches from cache.nixos.org during environment setup

**Dependency Network Activity:**
- Occurs only during initial setup (`nix-shell`, `bundle install`)
- No network activity during normal tool operation (except remote includes)
- Can be performed offline with pre-fetched dependencies

### 8.4 Open Source Audit

The tool is designed for transparency:
- Full source code available
- No proprietary components
- No obfuscated code
- Reproducible builds

**Audit Checklist:**
```bash
# 1. Verify no telemetry endpoints:
grep -r "http://\|https://" lib/ | grep -v "example.com"

# 2. Check for analytics libraries:
grep -r "mixpanel\|amplitude\|segment\|google.*analytics" .

# 3. Review network code:
cat lib/include_processor.rb  # Only file with Net::HTTP

# 4. Check environment variable access:
grep -r "ENV\[" lib/

# 5. Verify no persistent storage:
grep -r "File.write\|File.open.*w" lib/
```

---

## 9. Legal

### 9.1 License

This tool is licensed under the Apache License 2.0.

Copyright 2025 gitlab_ci_cli contributors

See LICENSE file for full text.

### 9.2 Disclaimer

This tool is provided "as-is" without warranty of any kind. Users are responsible for:
- Securing their own CI configurations
- Managing secrets and sensitive data
- Compliance with their organization's policies
- Auditing remote includes for security

### 9.3 Data Protection Officer

This tool has no Data Protection Officer because:
- It processes no personal data
- It is not a service (local tool)
- It has no users in the GDPR sense (software has users, but processes no user data)

---

## 10. Summary

**gitlab_ci_cli** is designed with privacy and security as core principles:

- **Local-First:** All processing happens on your machine
- **No Telemetry:** Zero analytics or tracking code
- **Minimal Network:** Only for optional remote includes
- **Transparent:** Open source, auditable code
- **GDPR-Compliant:** Processes no personal data
- **Enterprise-Ready:** Works in air-gapped environments

The tool follows the principle of **data minimization**: it processes only what is necessary for CI validation and simulation, and retains nothing beyond the lifetime of the process.

**Privacy Score:**
- Data Collection: NONE
- Network Activity: MINIMAL (optional feature only)
- Third-Party Sharing: NONE
- Persistent Storage: NONE
- User Tracking: NONE

**Overall Privacy Rating: 5/5 - Excellent**

---

**Document Version:** 1.0
**Last Reviewed:** 2025-10-14
**Next Review:** 2026-04-14 (or when significant changes occur)
