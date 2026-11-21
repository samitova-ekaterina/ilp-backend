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
