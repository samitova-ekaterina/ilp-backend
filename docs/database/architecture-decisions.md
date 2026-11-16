# Architecture decisions

This document explains the choices that shape the whole database. Each choice is given together with its reason, because a rule without a reason cannot be checked or defended.

## A relational database

The data of ILP are entities that depend on one another under strict rules: an answer belongs to a task and to a learning link, a homework consists of exercises, a level belongs to a scale. Changes often touch several tables at once and must happen together or not at all, for example an answer together with its statistics event, or the erasure of everything a user owns. This is the case a relational database with normalization and transactions is made for. The structure is normalized to the third normal form; the few places where a value is repeated on purpose are named in [integrity-and-transactions.md](integrity-and-transactions.md).

## Normalization

The structure was brought to the third normal form table by table, by putting three questions to every table.

| Form | The question | How it is answered here |
|---|---|---|
| First | Does every column hold one value, and can every row be told apart? | Every table has a primary key. A list is never packed into a text column: the target words of a task are rows of a link table, the members of a group are rows of `group_membership`. The only structured values are the five JSON columns, which are described and justified in [json-structures.md](json-structures.md) |
| Second | Does every column depend on the whole key and not on a part of it? | The question matters for tables with a composite key, the link tables. Their extra columns describe the pair itself: `homework_exercise.sort_order` is the place of this exercise in this homework, not a property of the exercise or of the homework |
| Third | Does a column depend on another column that is not the key? | A fact about a thing lives in the table of that thing. An answer stores its task and reaches the exercise and the material through it; the consent age belongs to the country, not to the user. A value that can be computed is not stored: the number of scored tasks of a competition held in a lesson follows from the exercise, and whether a word bank contains similar words follows from the bank |

The three places where a value is repeated on purpose, and why the copies cannot diverge, are listed in [integrity-and-transactions.md](integrity-and-transactions.md).

## PostgreSQL 17

PostgreSQL is the database named in the technology stack of the project. Three of its features are used directly. The `jsonb` type stores the body of a task, whose shape depends on the exercise type, in a form the database can validate and index. Partial unique indexes express rules such as "one open membership per learner and group" that an ordinary unique constraint cannot express. The clause `NULLS NOT DISTINCT`, available since version 15, lets a unique rule treat an empty value as a value. The minimum version is 17, which is supported until November 2029. No feature of a particular hosting provider is used, so the database is deployed the same way on a laptop, on the machine of a reviewer and on any hosting.

## One database management system and one database

The rubric allows a second system for analytics when the topic justifies it. Here it does not. The statistics of ILP are counted in events produced by learners answering tasks, a volume PostgreSQL handles without effort, and keeping them in the same database gives two things an external store would take away: the answer and its statistics event are written in one transaction, so the two can never disagree, and the event refers to the reference tables by real foreign keys, so an event with a non-existent exercise type cannot be stored. A separate analytical system would add a data pipeline, a second deployment and a new place for errors without solving any problem the project has.

## Two schemas as two layers

The database has two layers, and each is a schema of its own.

| Schema | Layer | What is in it | Who may change it |
|---|---|---|---|
| `core` | Operational data | Everything the product works with: users, materials, exercises, answers, levels | The application |
| `stats` | Anonymous statistics | Events without personal data, and a monthly summary built from them | The application may only add events; nobody edits or deletes them |

The requirement of the product is that statistics are kept apart from personal data and connected to them by a random code only. Separate schemas make this visible and enforceable: rights are granted per schema, and the table that maps a learning link to its random code lives in `core`, closed to the reading role, and is erased together with the link. After that the events in `stats` cannot be connected to a person by any query. The summary `stats.mv_statistics_summary` is the third step of the same flow: raw events are written once, and reports read the aggregated summary. The default schema `public` is not used, because everything tends to end up there by habit.

## Structure is created by migrations only

No object is created by hand. Every change is a Liquibase changeset written in plain SQL, kept in Git and applied in order. The reasons and the procedure are described in [versioning.md](versioning.md).

## Naming conventions

All names are English, in lower case, with words joined by underscores. A name is never put in quotation marks, which is why words reserved in SQL are avoided: the table of users is `app_user`, the table of groups is `study_group`, an ordering column is `display_order` or `sort_order`. Tables are named in the singular, so that a table and the Java class mapped to it carry the same name, and a column that refers to another table is named after it with the ending `_id`. Spring derives exactly these column names from field names, so no mapping has to be written by hand.

Every constraint has a name given by the author, not generated by the database, because the name is the only thing an error message shows. `ck_homework__due_after_assigned` tells what went wrong; `homework_check1` does not.

| Prefix | Object | Example |
|---|---|---|
| `pk_` | Primary key | `pk_answer` |
| `fk_` | Foreign key | `fk_answer__task` |
| `uq_` | Unique constraint or unique index | `uq_app_user__email` |
| `ck_` | Check constraint | `ck_learning_link__teacher_present` |
| `ix_` | Index for performance | `ix_answer__learning_link_answered_at` |
| `trg_` | Trigger | `trg_scale_level__log_level_change` |
| `v_`, `mv_` | View, materialized view | `v_revision_queue`, `mv_statistics_summary` |

After the prefix comes the table name, then two underscores, then the columns or the meaning. Two underscores are needed because table names already contain single ones. Names are kept under 63 characters, the limit after which PostgreSQL silently cuts a name.

## Keys

Every entity table has one surrogate primary key `id`, a `bigint` generated by the database. Real data change: an e-mail address can be replaced, a name corrected. If the address were the key, every table that refers to the user would have to be rewritten when it changes; a number never changes. What is unique by meaning, such as the e-mail address, is protected by a separate unique constraint, because a surrogate key alone does not prevent two users with the same address.

A link table for a plain many-to-many relationship has a composite primary key of its two foreign keys, so a pair cannot be stored twice. Where the same pair may truthfully occur again, for example a learner who left a group and came back, the row is a record with history: it has its own `id` and dates, and a partial unique index allows only one open record.

Values of `id` are never shown outside. An invitation, a summary link and a statistics code use separate random values, because consecutive numbers can be guessed and reveal how many users the system has.

## Data types

| What is stored | Type | Why |
|---|---|---|
| A moment in time | `timestamptz` | A teacher and a learner may live in different time zones while the moment is one. The type stores it in UTC and converts only for display |
| A calendar day | `date` | The next revision day or the day of a statistics event has no time of day; storing one would add false precision |
| The time zone of a user | `text`, a full name such as `Europe/Vilnius` | A full name carries the daylight saving rule; an offset such as `+2` would shift reminders by an hour in summer |
| Any text | `text` | PostgreSQL gains nothing from a length limit; where the length is limited by meaning, a check constraint says so |
| A value from a fixed list | `text` with a check constraint | The database rejects a misspelt status, a new value is one small migration, and the column maps to a Java enumeration without configuration |
| Yes or no | `boolean`, never empty | A third state "unknown" would force every condition in the code to handle three cases |
| Counters and ordinal numbers | `integer` | Whole by meaning and far from the limit; `bigint` is kept for keys |
| Fractions | `numeric` with a fixed scale | The ease factor of spaced repetition is recalculated many times, and binary fractions would drift |
| A duration | `integer` in milliseconds, with the unit in the column name | A whole number adds and compares without surprises, and `response_time_ms` cannot be mistaken for seconds |
| Data whose shape depends on the exercise type | `jsonb` | Only where ordinary columns are impossible; see [json-structures.md](json-structures.md) |
| Files | Not stored; a `text` column holds the address of the file | Large files inflate the database and slow down backups |
| Hashes | `text` | The hash string carries its own algorithm and parameters |
| A random code | `uuid` | A ready type for a value that cannot be guessed |

## Comments in the database

Every table and every column has a comment stored in the database, in English. The data dictionary is generated from these comments, so it is not a separate text that can become outdated. A comment on a column says what an empty value means, and a column with personal data starts its comment with the words "Personal data".
