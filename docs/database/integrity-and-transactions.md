# Data integrity and transactions

The rule behind this database is that a wrong row should be impossible to store, not merely unlikely. The application checks what a user types, but the last line of defence is the database itself: whatever path the data take, the same constraints apply. This document goes through the kinds of rules the database enforces and then through the places where several changes must happen together.

## What the database refuses to store

| Kind of rule | How many | What it protects | Example |
|---|---|---|---|
| Primary key | 57, one per table | Every row can be addressed | `pk_answer` |
| Foreign key | 119 | A row cannot point to something that does not exist | `fk_answer__task`: an answer always belongs to an existing task |
| `NOT NULL` | 260 of 377 columns | A value that must be known is known | `answer.answered_at` |
| Unique constraint | 45 | What is unique by meaning stays unique | `uq_app_user__email` |
| Partial unique index | 6 | Uniqueness that holds only for some rows | `uq_group_membership__active`: one open membership per learner and group |
| Check constraint | 96 | Values and combinations of values make sense | `ck_homework__due_after_assigned` |

### Empty values have a meaning

A column accepts an empty value only when emptiness says something, and the comment of the column states what. `lesson.ended_at` is empty while the lesson is in progress; `scale_level.current_cefr_level_id` is empty while there are no data for that scale, and the screen shows "no data" instead of a guessed level. States that have a moment of occurrence are stored as that moment and not as a flag: an archived exercise has `archived_at`, a revoked invitation has `revoked_at`. One column then answers both whether it happened and when.

### Values from fixed lists

A status or a kind is stored as text with a check constraint that lists the allowed values, for example `ck_answer__result` allows `correct`, `incorrect` and `awaiting_review`. The database rejects a misspelt value, and adding a new one is a small migration. Lists that carry more than a name, such as exercise types or CEFR levels, are reference tables, and rows refer to them by foreign keys with `ON DELETE RESTRICT`, so a value in use cannot be removed.

### Rules about several columns

Many rules concern a combination of columns, and these are the ones an application most easily gets wrong.

| Rule | Constraint | What it prevents |
|---|---|---|
| Exactly one of two parents is set | `ck_flag__one_target`, `ck_lesson__one_target`, `ck_image__one_target`, `ck_feature_toggle__one_target`, `ck_presentation_item__one_target` | A flag attached both to a task and to an exercise, or to neither |
| An end is not before its start | `ck_lesson__ended_after_started`, `ck_learning_link__ended_after_started`, `ck_consent__withdrawn_after_given` and others | A lesson that ended before it began |
| A link with a teacher has the teacher while it is open | `ck_learning_link__teacher_present` | An active link pointing to nobody |
| The kind of a link agrees with its columns | `ck_learning_link__kind_consistency` | A self-directed link with a teacher, or a link with a teacher that owns a course |
| A competition is either held in a lesson or matched by level | `ck_competition__lesson_or_matched` | A competition in a lesson with a number of scored tasks that could contradict the exercise, or one outside a lesson without that number |
| Access after the end belongs to a closed link with a teacher and lasts at most 365 days | `ck_learning_link__access_after_end` | Access left on an open or a self-directed link, or for an unlimited time |
| A material without an owner has a day of deletion, and only such a material has one | `ck_material__ownerless_is_retained` | A material kept forever after its owner erased the account |
| Active time is not longer than response time | `ck_answer__active_time_within_response` | An impossible measurement |
| The ease factor does not fall below 1.30 and the interval below one day | `ck_revision_record__ease_min`, `ck_revision_record__interval_positive` | A broken state of spaced repetition |

### Uniqueness that depends on a condition

Some rules cannot be written as an ordinary unique constraint, because they hold only for rows in a certain state.

| Index | Rule |
|---|---|
| `uq_consent__active` | A user has one consent in force of each kind; withdrawn consents stay as history |
| `uq_group_membership__active` | A learner has one open membership in a group, but may leave and come back |
| `uq_learning_link__open_triple` | One open link per learner, teacher and language |
| `uq_learning_link__open_self_directed` | A self-directed learner has one open course per language. The previous index does not cover this, because the teacher is empty in such a link and empty values never collide |
| `uq_material__folder_part` | Parts of a book are numbered without repetition inside a folder |
| `uq_topic__catalogue_name` | A topic of the common catalogue has a unique name; private topics are unique per owner |

One rule goes the other way. A revision record is unique per learning link, task and part of the task, and the part is empty when a task has a single part. `uq_revision_record__link_task_part` is declared with `NULLS NOT DISTINCT`, so two records with an empty part for the same task are rejected as duplicates.

### What happens to dependent rows on delete

Every foreign key states what happens when the row it points to is deleted. There is no foreign key left with the default behaviour.

| Action | How many | When it is used | Example |
|---|---|---|---|
| `CASCADE` | 66 | The child has no meaning without the parent | Tasks go with their exercise, answers with their learning link |
| `RESTRICT` | 37 | The parent must not disappear while it is in use | A reference value, a word used by a task, a folder with subfolders |
| `SET NULL` | 16 | The child keeps its meaning without the parent | An answer stays when its homework assignment is removed; a closed link stays when the teacher erases the account |

In everyday work nothing is deleted at all: an exercise is archived or excluded, an invitation is revoked, a link is closed. Real deletion is performed only by the procedure that erases personal data and by the clean-up of retained materials, both described in [personal-data.md](personal-data.md).

### Values repeated on purpose

The structure is in the third normal form with three deliberate exceptions, each guarded so that the copies cannot diverge or are not meant to stay equal.

| Where | What is repeated | Why it is safe |
|---|---|---|
| `pronunciation_choice.language_id`, `word_pronunciation.language_id` | The language of the pronunciation variant and of the word | The column takes part in composite foreign keys, so the database rejects a British variant attached to a Russian word. The repetition also makes "one choice per language" enforceable |
| `stats.statistics_event` | Exercise type, scale and level at the moment of the event | An event is a snapshot. It must keep the level the learner had then, and it must not refer to the learning link at all |
| `stats.mv_statistics_summary` | Aggregates of the events | A materialized view is derived data by definition and is rebuilt from the events |

## Transactions

A constraint protects one row or one relationship. A transaction protects a change that spans several rows: either all of it is stored or none.

| Change | Why it must be one transaction | Who guarantees it |
|---|---|---|
| An answer, the update of its revision record and its statistics event | Otherwise the schedule of repetition and the statistics would disagree with the answers | The application writes the three in one transaction; one database makes this possible |
| A change of the current level and its record in the history | A level must never change without a trace | The trigger `trg_scale_level__log_level_change` writes the record inside the same statement, so no code path can skip it |
| Erasure of personal data | A half-erased account is worse than an untouched one | The procedure `core.erase_personal_data` runs in the transaction of the caller and contains no commit. A test with a failure injected at the last step left every row in place and the request still marked as confirmed |
| A migration | A structure changed halfway cannot be repaired by hand reliably | PostgreSQL runs data definition statements inside transactions, and Liquibase applies each changeset in its own transaction. A failed changeset leaves nothing behind |
| Refreshing the statistics summary | Readers must not see an empty or half-built summary | `REFRESH MATERIALIZED VIEW CONCURRENTLY` replaces the content in one step without blocking readers |

The default isolation level of PostgreSQL, read committed, is sufficient for these cases. Two rules that could be broken by simultaneous sessions, one open link and one open membership, are enforced by unique indexes, which hold under any isolation level: the second session receives an error instead of creating a duplicate.

## How the rules were checked

Every rule added after the first version of the structure was tested from both sides on a database with test data: a row that must be accepted and a row that must be rejected. Each migration was also applied to an empty database, rolled back and applied again. The scenario queries in [scenario-queries.sql](scenario-queries.sql) confirm that the tables answer the questions the product asks.
