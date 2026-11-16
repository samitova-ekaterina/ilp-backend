# ILP database documentation

ILP is a web system that turns PDF study materials into interactive exercises and repeats them at growing intervals, adapting to each learner. Its users are private language teachers, their learners from the age of 14 and people who study on their own. This folder documents the database of the system: what it stores, why it is built this way and how to check it.

The database runs on PostgreSQL 17 and is created only by Liquibase migrations kept in Git. Everything below describes the state after the last migration, `0050`.

## The database in numbers

| What | How many |
|---|---|
| Schemas | 2: `core` for operational data and `stats` for anonymous statistics |
| Tables | 57 |
| Columns | 377, of which 260 do not accept an empty value |
| Foreign keys | 119 |
| Check constraints | 96 |
| Unique constraints and unique indexes | 51 |
| Indexes added for performance | 70 |
| Views | 4 and 1 materialized view |
| Functions, procedures, triggers | 2 functions, 3 procedures, 1 trigger |
| Roles | 3 |
| Migrations | 50 files, 129 changesets |

## Where to find what

| Document | What it answers |
|---|---|
| [architecture-decisions.md](architecture-decisions.md) | Why a relational database, why PostgreSQL, why one database with two schemas, and the conventions every table follows |
| [schema.md](schema.md) | The logical schema: an overview of nine colour-coded blocks and a detailed diagram of each block |
| [data-dictionary.md](data-dictionary.md) | Every table and column: type, keys, constraints and the meaning of an empty value |
| [integrity-and-transactions.md](integrity-and-transactions.md) | How the database keeps the data correct and where transactions matter |
| [roles-and-access.md](roles-and-access.md) | The three roles, the application account and how passwords are stored |
| [personal-data.md](personal-data.md) | Which columns hold personal data, how they are masked, erased and kept out of the statistics |
| [json-structures.md](json-structures.md) | The five JSON columns: why they exist and how their structure is described and checked |
| [database-objects.md](database-objects.md) | Views, the materialized view, functions, the trigger and procedures |
| [indexes.md](indexes.md) | Which indexes exist and why, and which were left out on purpose |
| [reference-and-test-data.md](reference-and-test-data.md) | What the reference tables contain and which edge cases the test data cover |
| [versioning.md](versioning.md) | How the structure is versioned, rolled back and deployed from scratch |
| [scenario-queries.sql](scenario-queries.sql) | Fourteen queries that answer real questions of the product on the test data |
| `schema.sql` | The whole structure as one SQL script, exported from the database |
| [`src/main/resources/db/changelog/`](../../src/main/resources/db/changelog/) | The migrations themselves |

## How to deploy the database

The steps for deploying the database from scratch, with and without the test data, are in the [README of the repository](../../README.md).
