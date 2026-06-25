# Security Policy

Lid Awake controls local macOS power behavior and includes an admin-approved privileged helper for closed-lid mode. Treat helper, XPC, signing, and `pmset` changes as security-sensitive.

## Reporting A Vulnerability

Please do not publish exploit details in public issues, pull requests, or discussions.

When the repository is published on GitHub, use a private security advisory if it is enabled. Before that is available, email `thuongtin@gmail.com` and include `Lid Awake security report` in the subject.

Useful reports include:

- A clear description of the issue.
- Steps to reproduce.
- macOS version and hardware model.
- Whether helper approval was enabled.
- Whether the Mac was on battery power or AC power.
- Relevant logs, if they do not expose private data.

## Scope

Security-sensitive areas include:

- Privileged helper authorization and XPC boundaries.
- `pmset` command execution and closed-lid restore behavior.
- `SMAppService`, LaunchDaemon plists, and helper approval.
- Code signing identifiers and local staging behavior.
- Any future release packaging, notarization, or auto-update mechanism.

Reports about denial of service, local privilege boundary mistakes, unsafe command execution, incorrect helper trust decisions, or irreversible power-setting changes are in scope.

## Not In Scope

- Reports that require physical access and no change to Lid Awake behavior.
- General macOS power-management limitations that the app clearly documents.
- Missing notarization for local ad-hoc builds created from source.
- Social engineering reports without a software vulnerability.
