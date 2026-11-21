# Testing conventions

These rules apply to the tests of both projects, `ilp-backend` and `ilp-frontend`. A new test follows them from its first line; this is checked in code review.

## Back end

Tests live in `src/test/java`, in the same package as the class they test. The name of the test class tells what kind of test it is:

| Name | Kind | May use |
|---|---|---|
| `...Test` | Fast test | Only the code under test and test doubles: no database, no network, no files outside the test |
| `...IT` | Integration test | The assembled application and a real PostgreSQL |

## Front end

- A component test is named `Name.test.tsx` and lies next to the component `Name.tsx`.
- End-to-end tests lie in the folder `e2e` at the root of the project.

## Names and structure

- The name of a test is a plain phrase that says what must happen: `unexpectedFailureReturns500WithoutInternalDetails`, not `testHandler2`.
- A test has three parts in this order: preparation, action, check. One test checks one behaviour.
- A test checks behaviour, not implementation: it looks at the response, the stored data or the log line, not at how the code produces them.
- Tests do not depend on each other or on the order in which they run. A test that fails and then passes without a change in the code is treated as a defect and is fixed, not rerun.

## Running

Each project has one command that runs all its tests:

| Project | Command |
|---|---|
| `ilp-backend` | `./gradlew check` |
| `ilp-frontend` | `npm run check` |
