# Defects found by automated tests

This list keeps every defect that an automated test found in `ilp-backend` or `ilp-frontend`: what was wrong, which test found it and how it was fixed. It shows what the tests are worth and where the code was weak.

## How to add a record

Add a row at the bottom of the table when a test fails because of a real defect in the code, in the settings or in a migration. A test that failed because the test itself was wrong is not a defect and is not recorded.

- **Date** - the day the defect was found.
- **Project** - `ilp-backend` or `ilp-frontend`.
- **Found by** - the name of the test or of the check, as it is written in the code.
- **What was wrong** - the behaviour that was observed and the behaviour that was expected.
- **Fix** - what was changed, with the number of the commit or of the pull request.

## Records

| Date | Project | Found by | What was wrong | Fix |
|---|---|---|---|---|
| 2026-11-22 | `ilp-backend` | Job "Libraries: licences and vulnerabilities" of the workflow `checks.yml` | Every job downloaded all libraries again on every run: the jobs shared one cache, and it was saved by the job that needs almost no libraries. With two runs for one commit the library repository answered "429 Too Many Requests" and the run failed before any check started. Expected: a job downloads a library once and takes it from the cache afterwards | Every job has a cache of its own (pull request #33) |
