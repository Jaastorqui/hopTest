
## Unit tests

`bin/hop-test.sh` runs `hop/workflows/run-tests.hwf`, which runs every test named in its
**Run Pipeline Tests** action. Currently one: `02-accounts-merge`, the merge, with CSV
fixtures on both legs and no database at either end.

Three things that are not obvious and cost an afternoon:

- **A golden data set replaces the transform's output row** with the mapped fields. Put one
  mid-stream and everything downstream breaks on a missing field. It belongs on the last
  transform before the output.
- **The pipeline still writes to the real target** unless you switch the output off. The test
  carries a `REMOVE_TRANSFORM` tweak on `→ accounts` for exactly this reason. Without it the
  fixtures land in `accounts`.
- **An unparseable test list fails silently as a pass.** If the `<test_names>` block in the
  `.hwf` is malformed the action runs zero tests and reports success. Verify a new test can
  actually fail before trusting it.
