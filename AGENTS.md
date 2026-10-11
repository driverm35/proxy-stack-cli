# Agent notes

- Read README.md and the module map in `lib/` before changing behavior.
- Keep commits small and conventional (`feat:`, `fix:`, `test:`, `ci:`, `docs:`, `chore:`).
- After a change, run the tests that cover it. Before finishing, run the CI-equivalent checks: `shellcheck`, `shfmt -d`, and `bats tests/unit`.
- Do not commit secrets, tokens, passwords, `.env` files, or private keys.
- Do not continue after failing tests. Fix the failure or add a regression test and make it pass.
- Editing files, running tests, committing, and pushing are expected when the task asks for them.
- Unit tests and config rendering stay local and must not change the host firewall, SSH, or installed proxy services. Package-level checks belong in GitHub Actions or an isolated container.
