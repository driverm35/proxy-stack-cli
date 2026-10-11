# Contributing

Issues and pull requests are welcome. Keep changes focused, and do not commit secrets or real server inventories.

## Development

The CLI is Bash for Ubuntu and Debian. On Windows, run the unit tests with Git Bash. Do not install Dante, Squid, or Caddy on a workstation just to edit docs.

```bash
make check
```

`make check` runs ShellCheck, `shfmt -d -i 2 -ci`, and `bats tests/unit`. Integration tests live in `tests/integration` and run in GitHub Actions.

## Commits

Use a conventional subject such as `fix: keep SSH allowed before ufw enable`. Run the tests that cover your change before you push. Do not merge with a failing unit test.

## Pull requests

Describe the user-visible change and list the checks you ran. The pull request template has a short checklist.
