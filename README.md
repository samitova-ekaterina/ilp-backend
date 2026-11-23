# ILP

[![Checks](https://github.com/samitova-ekaterina/ilp-backend/actions/workflows/checks.yml/badge.svg?branch=develop)](https://github.com/samitova-ekaterina/ilp-backend/actions/workflows/checks.yml)

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
| `liquibase.properties` | The name of the migration account and the location of the migrations; no address and no password |

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

The steps assume PostgreSQL 17 and Liquibase 5 are installed. Neither the address of the database nor a password is stored in the repository: Liquibase reads the address from the environment variable `LIQUIBASE_COMMAND_URL` and the password of the migration account from `LIQUIBASE_COMMAND_PASSWORD`.

1. As the PostgreSQL administrator, create the migration account and the database. The account needs the right to create roles, because the roles of the system are created by a migration. The encoding is stated explicitly, so that the database does not inherit whatever the server was installed with:

   ```sql
   CREATE ROLE ilp_owner LOGIN CREATEROLE PASSWORD '...';
   CREATE DATABASE ilp OWNER ilp_owner ENCODING 'UTF8' TEMPLATE template0;
   ```

2. Set `LIQUIBASE_COMMAND_URL` to the JDBC address of the database, in the form `jdbc:postgresql://<host>:<port>/ilp`, and `LIQUIBASE_COMMAND_PASSWORD` to the password of `ilp_owner`, then run in the root of the repository:

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

## How the application is deployed

The application runs on Render and uses a PostgreSQL 17 database on Neon; both are in the region Frankfurt, on free plans.

The public address is `https://ilp-backend-7jv7.onrender.com`. It has no start page; these addresses answer:

| Address | What it shows |
|---|---|
| [`/actuator/health`](https://ilp-backend-7jv7.onrender.com/actuator/health) | The state of the application |
| [`/swagger-ui.html`](https://ilp-backend-7jv7.onrender.com/swagger-ui.html) | The description of the API |
| [`/api/v1/languages`](https://ilp-backend-7jv7.onrender.com/api/v1/languages) | The first request of the API: the list of languages |

- [`Dockerfile`](Dockerfile) builds the image: the first stage builds the application file with Gradle, the second holds only Java 25 and that file.
- [`render.yaml`](render.yaml) describes the service for Render: the plan, the region, the health check and the names of the settings.
- Render builds and starts a new version only when all checks of the commit have passed.

The service reads three secrets from the closed settings of the platform; none of them is in the repository:

| Setting | What it holds |
|---|---|
| `ILP_DB_URL` | The JDBC address of the database |
| `ILP_APP_PASSWORD` | The password of `ilp_app`, the account the application works under |
| `LIQUIBASE_COMMAND_PASSWORD` | The password of `ilp_owner`, the account that applies the migrations at start-up |

The free service on Render stops after 15 minutes without requests, so the first request after a pause is slow. In two runs on 23.11.2026 the first answer came after about two and about three minutes.

The first measurement under a small load is described in [`docs/load-testing.md`](docs/load-testing.md).

### Preparing an empty database for the application

At start-up the application applies the migrations as `ilp_owner` and then connects as `ilp_app`. So, unlike the manual way above, the account of the application must exist before the first start:

1. Create `ilp_owner` with the right to create roles, and the database `ilp` owned by it. On Neon both are created in the Neon Console: a role created there has the right to create roles.
2. As `ilp_owner`, create the group role and the account of the application:

   ```sql
   CREATE ROLE ilp_write NOLOGIN;
   CREATE ROLE ilp_app LOGIN PASSWORD '...';
   GRANT ilp_write TO ilp_app;
   ```

   The migration that creates the roles skips a role that already exists.
3. Start the application: it applies the migrations without the test data and begins to serve requests.

## Security

The repository contains no password, key or token: the password of the migration account is read from an environment variable, and `.gitignore` excludes local settings files. Passwords of users are stored only as Argon2id hashes.
