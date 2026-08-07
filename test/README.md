# Tests

Dependency-free test suite: bash + jq only.

    ./test/run-tests.sh

Tests run `relay-run.sh` against `test/fixtures/fake-cli`, a stub that records
its argv (one argument per line) to `$FAKE_CLI_LOG` and exits with
`$FAKE_CLI_EXIT`. No real AI CLI is invoked and no network access is needed, so
the suite asserts on the exact command line ai-relay builds.

Each test runs in its own `mktemp -d` sandbox with an isolated
`AI_RELAY_HOME`, so nothing touches your real config.
