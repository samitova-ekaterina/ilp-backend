# Testing conventions

These rules apply to the tests of both projects, `ilp-backend` and `ilp-frontend`. A new test follows them from its first line; this is checked in code review.

## Back end

Tests live in `src/test/java`, in the same package as the class they test. The name of the test class tells what kind of test it is:

| Name | Kind | May use |
|---|---|---|
| `...Test` | Fast test | Only the code under test and test doubles: no database, no network, no files outside the test |
| `...IT` | Integration test | The assembled application and a real PostgreSQL |

An integration test extends `IntegrationTestBase`. The base class starts one PostgreSQL 17.5 in a Docker container for the whole run, creates the database accounts in it with passwords generated for this run, and starts the application against it. The test of the migrations, `MigrationsIT`, starts its own empty database.

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

On the back end the command runs the check of the code format, the fast tests, the integration tests, the coverage check and the check of the licences of the libraries. The integration tests need Docker to be running. Parts of it can be run separately:

| Command | What it runs | Needs Docker |
|---|---|---|
| `./gradlew test` | The fast tests | No |
| `./gradlew integrationTest` | The integration tests | Yes |
| `./gradlew spotlessApply` | Rewrites the code in the agreed format | No |

## Coverage

- Coverage of the back end is measured by JaCoCo from the fast and the integration tests together.
- The threshold is 80 % of lines; `./gradlew check` fails below it. The class that starts the application and the configuration classes are not counted.
- The report is written to `build/reports/jacoco/test/html/index.html`; it shows lines, instructions and branches.
- When coverage falls below the threshold, tests are added. The threshold is not lowered and the list of classes that are not counted is not extended.

## Checks on every push

The workflow `.github/workflows/checks.yml` runs on every push to any branch, on every pull request into `develop` or `main`, and by hand. Its jobs go in this order: code format; build; tests and coverage; libraries (licences and known vulnerabilities, see [`library-checks.md`](library-checks.md)). A failed job makes the whole run fail, and a branch with a failed run is not merged. The reports of the tests, the coverage and the licences are saved with the run.
