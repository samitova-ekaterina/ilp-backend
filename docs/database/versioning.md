# Versioning of the database structure

The structure of the database is code. It is written as migrations, kept in Git next to the application and applied by a tool, never by hand. This document describes how that works and how to check it.

## The tools

| What | Choice | Why |
|---|---|---|
| Migration tool | Liquibase 5 | It records which changes a database has received and applies only the missing ones, on any database, in the same order |
| Format of migrations | Plain SQL with Liquibase comments | The SQL that runs is the SQL that is read and reviewed. Nothing is generated from another notation, and every PostgreSQL feature is available |
| Version control | Git, from the first migration | Every change of the structure has an author, a date and a message |

## How a change is made

A migration is a file in `src/main/resources/db/changelog/migrations/`, numbered in order and named after what it does, for example `0035_revision_record_part.sql`. The master file `db.changelog-master.yaml` lists the migrations in the order they are applied.

A file consists of changesets. A changeset is one logical step with an identifier and, after it, the statements that undo it:

```sql
--changeset samitava:0036-exercise-typo-tolerance
ALTER TABLE core.exercise ADD COLUMN is_typo_tolerated boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN core.exercise.is_typo_tolerated IS 'Whether a typed answer with a typo is accepted. Set by the author of the material.';
--rollback ALTER TABLE core.exercise DROP COLUMN is_typo_tolerated;
```

Three rules hold for every migration.

**A migration that has been applied is never edited.** Liquibase stores a checksum of every changeset and refuses to continue if an applied one has changed. A mistake is corrected by a new migration. The history shows this honestly: migration `0024` fills a table of level steps, and migration `0031` removes that table after it turned out to repeat the CEFR levels. Both stay in the repository, and a database built from scratch passes through both.

**Every changeset has a rollback.** The rollback restores the structure and, where the change moved data, the data. Migration `0031` converts six columns and drops a table; its rollback recreates the table and converts the columns back.

**Rights are granted in the migration that creates the object.** A new table is not visible to the reading and writing roles until the migration says so.

Comments in migrations are written only where a decision is not obvious from the SQL, and they give the reason, not a retelling of the statement.

## What Liquibase keeps in the database

Liquibase creates two tables of its own in the schema `public`. `databasechangelog` has one row per applied changeset with its identifier, author, file, checksum and the moment it was applied; this is the version history of the database, stored in the database itself. `databasechangeloglock` prevents two runs from changing the structure at the same time.

Together with Git this gives two views of the same history: Git answers who wrote a change and why, and `databasechangelog` answers which changes a particular database has received and when.

## The history so far

| Migrations | What they did |
|---|---|
| `0001`-`0009` | The first wave of tables: schemas, reference tables, users and access, materials and parsing, lessons and homework, practice and revision, history and level, adaptation, statistics |
| `0010`-`0018` | The second and third waves: columns and tables for further stories of the product, including competitions |
| `0019`-`0024` | Reference data |
| `0025` | Roles and rights |
| `0026`-`0029` | Test data |
| `0030` | Indexes |
| `0031`-`0038` | Corrections found by reviewing the finished structure against the stories of the product |
| `0039`, `0040` | Test data for the corrected structure |
| `0041`-`0046` | Views, the function, the trigger, procedures, the materialized view |
| `0047`-`0050` | Retention of materials after an erasure and access after the end of lessons |

In total there are 50 migration files with 129 changesets, of which 7 are test data.

## How to check it

**From scratch.** The strongest check of a set of migrations is to apply all of them to an empty database. This was done repeatedly during the work, on a second database of the same server, each time ending with every changeset applied and no error. The commands are in [README.md](README.md).

**Rollback.** Every migration from `0021` on was also rolled back and applied again on a test database, and the structure after the rollback was compared with the structure before the migration.

**Without test data.** The structural migrations were applied without the test data to make sure that none of them depends on a test row.

To see the state of a database:

```
liquibase status
liquibase history
```

To roll back the last changeset:

```
liquibase rollback-count --count=1
```

## The structure as one script

The migrations are the source of the structure. For reading the structure in one piece, the file `schema.sql` in this folder contains it as a single SQL script, exported from a database built by the migrations:

```
pg_dump -U ilp_owner --schema-only --no-owner --schema=core --schema=stats ilp > schema.sql
```

The script is derived and is regenerated after a migration; it is never edited by hand.
