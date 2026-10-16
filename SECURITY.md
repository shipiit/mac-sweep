# Security policy

## Reporting a vulnerability

Do not open a public issue containing exploit details, credentials, private paths, or sensitive user data.

When private vulnerability reporting is enabled, use [Report a vulnerability](https://github.com/shipiit/mac-sweep/security/advisories/new). If that route is unavailable, open a minimal issue asking the maintainer for a private reporting channel without including the vulnerability details. Do not attach sensitive diagnostics until a private channel is agreed.

Include the affected version, a minimal reproduction using synthetic data, expected and actual behavior, potential impact, and any suggested fix. Coordinated disclosure gives the maintainer a chance to assess and remediate before details become public. No response or remediation deadline is guaranteed.

## Scope and limits

MacSweep performs local cleanup and system inspection. Cleanup protections include a defined catalog, protected-path checks, in-use checks, confirmation, and Trash by default. These controls reduce risk; they do not replace backups or careful review. Permanent deletion, process termination, maintenance, and service changes can have lasting effects.

Threat checks are heuristic and work alongside Apple XProtect. They are not a signature antivirus and do not provide Endpoint Security execution blocking. Download checks occur after downloads finish. Builds are currently ad-hoc signed and not notarised.

AI usage estimates are distinct from provider bills. Reading real Claude plan limits is opt-in and uses the Anthropic usage endpoint with the user's existing sign-in permission.

## Supported versions

Report findings against the latest release or current `main`. Older versions are not promised security backports. Review [release notes](https://github.com/shipiit/mac-sweep/releases) before installing or upgrading.
