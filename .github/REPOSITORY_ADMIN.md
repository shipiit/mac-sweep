# Repository administration

## Current boundary

The default branch is `main`. The versioned rules target the default branch plus both `main` and `master`; there is no need to rename the branch.

GitHub Free does not support enforcing these branch rules on a private repository. Committing the JSON files does **not** activate protection. The repository must be public, or use a plan that supports private-repository rules, before activation. Visibility changes require the owner's explicit decision; the activation script never makes the repository public.

## Proposed enforcement

- `Maintainer-only protected branch updates`: restrict matching branch creation and updates to the explicit bypass account `@iamrraj` (GitHub user ID 37672067). Other changes must be submitted through pull requests for the maintainer. Review settings include a code-owner review, dismissal of stale approvals, approval of the latest push, resolved review threads, and squash merges. The maintainer bypass is intentional for solo administration and direct authorized pushes.
- `Protected branch history integrity`: blocks force pushes and branch deletion, with no bypass actor. Admins can still edit or remove rules, so protect admin membership and account security.
- CODEOWNERS identifies the reviewer but does not grant permissions or activate protections.
- CI runs Swift builds/tests and website syntax checks. Both passed in GitHub Actions run 38941363932. The prepared update rules require `Swift build and tests` and `Website syntax`, bound to the GitHub Actions integration (15368), with up-to-date branch checks. The explicit maintainer bypass also covers these checks; it is not a guarantee that maintainer pushes are gated by CI.

## Activate and verify

After the owner makes the repository public:

```sh
python3 scripts/apply-repository-rules.py
gh api repos/shipiit/mac-sweep/rules/branches/main
gh api repos/shipiit/mac-sweep/rules/branches/master
```

The script upserts rules by name and reads back their settings. Review the repository Rules page after activation. It does not grant write roles or modify collaborators. Check collaborator/team access separately whenever authorizing another maintainer; update the explicit bypass actor only when the owner requests that access.

Do not test protection by attempting a destructive force push or branch deletion.

## Public release checks

Before changing visibility, review the entire Git history and release assets for secrets and personal data, confirm the intended license, and review collaborator/team permissions. This setup is not a comprehensive historical secret audit and does not choose a license for the owner.

Once public, enable private vulnerability reporting, secret scanning, and push protection where GitHub exposes those controls for the repository. Read back their actual status; documentation alone is not enforcement. Never put credentials in workflow files or give untrusted pull-request code a privileged `pull_request_target` workflow.
