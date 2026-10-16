# Repository administration

## Active protection

MacSweep is public. The default branch is `main`. Both named rulesets are active and have been read back from the GitHub API. They target the default branch plus `main` and `master`, including `master` if it is created later.

- [Maintainer-only protected branch updates](https://github.com/shipiit/mac-sweep/rules/25259497): only `@iamrraj` (GitHub user ID 37672067) is an explicit bypass actor for protected-branch creation and updates. Review rules require one approval, code-owner review, dismissal of stale approvals, approval of the latest push, resolved review conversations, and squash merges.
- [Protected branch history integrity](https://github.com/shipiit/mac-sweep/rules/25259495): force pushes and protected-branch deletion are blocked, with no bypass actor.
- Required checks are `Swift build and tests` and `Website syntax`, bound to the GitHub Actions integration (15368), with up-to-date branch checks. Both check names have passed in GitHub Actions.

The maintainer's explicit update/review bypass allows authorized direct pushes and solo administration; it also bypasses the required checks in that ruleset. It does not bypass the separate history rules. Administrators can edit repository rules, so admin membership and account security remain trusted boundaries. CODEOWNERS identifies review ownership; it does not grant repository access.

An older ruleset named `Protect` is disabled and has no target branches. It does not replace or weaken the two active rulesets above.

## Security settings

Secret scanning, secret-scanning push protection, dependency alerts, automated security fixes, and private vulnerability reporting have been enabled. Push protection covers supported secret patterns; it is not a guarantee that every credential or other sensitive value will be detected. Review security alerts and account permissions regularly.

The CI workflows use read-only repository permissions and an immutable checkout action reference, with persisted checkout credentials disabled. Untrusted pull-request code is not run in a privileged `pull_request_target` workflow.

## Reapply and verify

```sh
python3 scripts/apply-repository-rules.py
gh api repos/shipiit/mac-sweep/branches/main --jq '{name,protected}'
gh api repos/shipiit/mac-sweep/rules/branches/main
gh api repos/shipiit/mac-sweep/rules/branches/master
```

The script upserts rules by name and reads back their settings. It never changes visibility or grants collaborator access. GitHub omits default update-rule parameters in its response; the stored update rule uses the matching canonical representation.

Check collaborator/team permissions before authorizing another maintainer. Change the explicit bypass actor only when the owner requests that access. Do not test protection by attempting a destructive force push or branch deletion.

GitHub Free cannot enforce these rules if the app repository is changed back to private. A suitable paid organization plan is needed for private-repository enforcement.

## Release governance

Review the entire Git history and release assets for secrets and personal data, confirm the intended license, and inspect collaborator/team permissions before publishing additional material. This setup is not a comprehensive historical security audit and does not choose a license for the owner.
