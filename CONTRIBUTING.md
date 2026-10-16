# Contributing to MacSweep

MacSweep is a native SwiftUI app for macOS 15+ and Apple Silicon. Start with the [README](README.md), [product website](https://shipiit.github.io/mac-sweep-website/), or an existing [issue](https://github.com/shipiit/mac-sweep/issues).

## Report a problem or propose a feature

Use the issue templates. Explain the behavior you expected, what happened, and how to reproduce it. Include your macOS version and MacSweep version. Redact personal paths, network addresses, credentials, and conversation contents from diagnostics.

Report suspected vulnerabilities through the private route in [SECURITY.md](SECURITY.md), rather than a public issue.

## Make a change

1. Discuss substantial behavior or architecture changes in an issue first.
2. Fork the repository when it is public, or use an authorized feature branch. Create a descriptive branch such as `fix/scan-progress`.
3. Keep the change focused. Put system logic in `MacSweepCore` and presentation in the app target.
4. Run `make test` and `swift build` with Xcode 16 / Swift 6 on macOS 15 or later. Add regression coverage when changing cleanup, path checks, security rules, parsing, or other logic.
5. For UI changes, explain the affected screens and include redacted screenshots and accessibility checks. Website changes should be checked at phone and desktop widths with reduced motion.
6. Open a pull request against `main`. Describe the problem, the resulting behavior, and the checks you actually ran. Link the relevant issue.

Do not run cleanup or destructive operations against another person's data to demonstrate a fix. Use temporary test fixtures.

## Review and repository controls

`main` is the default branch; the active rules also cover `master` if created. The active branch policy restricts updates to `@iamrraj`. Contributors submit pull requests for the maintainer to review and merge. The maintainer is an explicit bypass actor for update/review rules so a solo maintainer is not locked out by self-review requirements. Separate history rules block force pushes and protected-branch deletion without a bypass.

CODEOWNERS declares review ownership; it does not itself grant write access or enforce branch protection. Repository administrators can edit repository rules, so admin membership remains a trusted role.

The repository is public and the rules are active. GitHub Free cannot enforce these rules if it becomes private again. See [repository administration](.github/REPOSITORY_ADMIN.md) for the verified rules and administration procedure.

## Conduct

Be respectful and specific. Discuss code and behavior rather than the person proposing a change. Do not post harassment, personal information, credentials, spam, or unrelated promotions. Maintainers may moderate or close reports that do not follow these guidelines.
