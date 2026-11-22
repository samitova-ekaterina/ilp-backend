# Testing conventions

These rules apply to the tests of both projects, `ilp-backend` and `ilp-frontend`. A new test follows them from its first line; this is checked in code review.

## Back end

Tests live in `src/test/java`, in the same package as the class they test. The name of the test class tells what kind of test it is:

| Name | Kind | May use |
|---|---|---|
| `...Test` | Fast test | Only the code under test and test doubles: no database, no network, no files outside the test |
| `...IT` | Integration test | The assembled application and a real PostgreSQL |

A fast test that checks a property on generated values instead of single examples is named `...PropertyTest` and is written with jqwik: a failing property prints the smallest value that breaks it.

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
| `./gradlew pitest` | The mutation tests | No |

## Coverage

- Coverage of the back end is measured by JaCoCo from the fast and the integration tests together.
- The threshold is 80 % of lines; `./gradlew check` fails below it. The class that starts the application and the configuration classes are not counted.
- The report is written to `build/reports/jacoco/test/html/index.html`; it shows lines, instructions and branches.
- When coverage falls below the threshold, tests are added. The threshold is not lowered and the list of classes that are not counted is not extended.

## Mutation tests

- PIT changes the code of the application in small ways, one change at a time, and runs the fast tests against every change. A change that no test notices shows a place where the tests check too little.
- The threshold is 80 % of noticed changes; `./gradlew pitest` fails below it. The class that starts the application and the table classes are not changed.
- The report is written to `build/reports/pitest/index.html`.
- The mutation tests take longer than the other tests, so they are not a part of `./gradlew check`; they run on every push as a job of their own.

## The saved API description

- The description of the API that is generated from the code is kept as a file: [`api/openapi.json`](api/openapi.json). The test `ApiDescriptionIT` compares the current description with this file and fails on any difference, so the API cannot change by accident.
- When the API is changed on purpose, the test fails and writes the new description to `build/api/openapi.json`. Copy that file over `docs/api/openapi.json` and commit it together with the change: the pull request then shows the change of the API as a change of this file.

## Checks on every push

The workflow `.github/workflows/checks.yml` runs on every push to any branch, on every pull request into `develop` or `main`, and by hand. Its jobs go in this order: code format; build; then three jobs side by side: tests and coverage, mutation tests, libraries (licences and known vulnerabilities, see [`library-checks.md`](library-checks.md)). A failed job makes the whole run fail, and a branch with a failed run is not merged. The reports of the tests, the coverage, the mutation tests, the licences and the vulnerabilities are saved with the run.
