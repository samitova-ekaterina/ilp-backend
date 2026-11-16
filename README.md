# ILP

ILP is a web system that turns PDF study materials into interactive exercises and repeats them at growing intervals, adapting to each learner. It is made for private language teachers, their learners from the age of 14 and people who study on their own.

This is the back-end repository of the project. At this stage it contains the database: the migrations that create it, its reference and test data, and its documentation. The application code will be added to the same repository at the next stages.

The project is a diploma project at the European Humanities University, academic year 2026/27. Author: Katsiaryna Samitava.

## What is in the repository

| Path | What it is |
|---|---|
| [`src/main/resources/db/changelog/migrations/`](src/main/resources/db/changelog/migrations/) | 50 Liquibase migrations in plain SQL: structure, reference data, roles, test data, indexes, views, functions and procedures |
| [`src/main/resources/db/changelog/db.changelog-master.yaml`](src/main/resources/db/changelog/db.changelog-master.yaml) | The order in which the migrations are applied |
| [`docs/database/`](docs/database/) | The documentation of the database; start with its [README](docs/database/README.md) |
| [`docs/database/data-dictionary.md`](docs/database/data-dictionary.md) | The data dictionary: every table and column |
| [`docs/database/schema.md`](docs/database/schema.md) | The logical schema in nine colour-coded blocks |
| [`docs/database/schema.sql`](docs/database/schema.sql) | The whole structure as one SQL script |
| `liquibase.properties` | The address of the database and the name of the migration account; no password |

## The database at a glance

PostgreSQL 17, two schemas: `core` for operational data and `stats` for anonymous statistics. 57 tables, 119 foreign keys, 96 check constraints, 4 views and a materialized view, a trigger, 2 functions and 3 procedures.

## Roles

| Role | For whom | In short |
|---|---|---|
| `ilp_read` | Reports, support, analysis | Reads the data; does not see e-mail addresses, names, password hashes, texts of notes or secret codes, and gets masked views instead |
| `ilp_write` | The application | Reads and changes the working tables; cannot change reference tables or the structure; may only add statistics events |
| `ilp_admin` | Migrations and administration | Everything in both schemas |

The roles are groups of rights without a login. The application connects with its own account, `ilp_app`, which is a member of `ilp_write` and is not a superuser. Details are in [`docs/database/roles-and-access.md`](docs/database/roles-and-access.md).

## How to deploy the database from scratch

The steps assume PostgreSQL 17 and Liquibase 5 are installed. No password is stored in the repository: the password of the migration account is read from the environment variable `LIQUIBASE_COMMAND_PASSWORD`.

1. As the PostgreSQL administrator, create the migration account and the database. The account needs the right to create roles, because the roles of the system are created by a migration. The encoding is stated explicitly, so that the database does not inherit whatever the server was installed with:

   ```sql
   CREATE ROLE ilp_owner LOGIN CREATEROLE PASSWORD '...';
   CREATE DATABASE ilp OWNER ilp_owner ENCODING 'UTF8' TEMPLATE template0;
   ```

2. Set `LIQUIBASE_COMMAND_PASSWORD` to the password of `ilp_owner` and run in the root of the repository:

   ```
   liquibase update
   ```

   On an empty database the expected summary is `Run: 129, Previously run: 0`.

3. To deploy without the test data, exclude the changesets marked with the context `test`:

   ```
   liquibase update --context-filter="!test"
   ```

   The expected summary is `Run: 122` and `Filtered out: 7`.

4. Create the account of the application outside the repository and give it the writing role only:

   ```sql
   CREATE ROLE ilp_app LOGIN PASSWORD '...';
   GRANT ilp_write TO ilp_app;
   ```

The test users all have the password `TestPassword1`; the database holds only its Argon2id hash. Their addresses are in the reserved domain `example.com`.

## Security

The repository contains no password, key or token: the password of the migration account is read from an environment variable, and `.gitignore` excludes local settings files. Passwords of users are stored only as Argon2id hashes.
