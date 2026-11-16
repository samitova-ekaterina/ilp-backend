# Reference data and test data

The database is delivered with two kinds of content, and the migrations keep them apart. Reference data are part of the product: without them the system cannot work, and they are the same in every installation. Test data exist to show that the structure works and to give a reviewer something to query; they are marked so that a real installation can leave them out.

## Reference data

Reference tables are filled by migrations `0019`-`0024` and `0037`, never by hand and never by the application, which has no right to change them. A new value is a new migration, so the content of the reference tables has the same history and review as the structure.

| Table | Rows | Content |
|---|---|---|
| `core.country` | 1 | Lithuania with the consent age of 14. The age comes from the reference table, not from the code, so another country is one row |
| `core.language` | 2 | English and Russian. A language is used both as the language of the interface and as the language studied; the structure does not depend on a particular language |
| `core.cefr_level` | 6 | A1, A2, B1, B2, C1, C2 |
| `core.scale` | 4 | Vocabulary, Grammar, Writing, Speech: the four scales on which a level is kept |
| `core.exercise_type` | 32 | The catalogue of exercise types. Each row carries the way the type is shown, whether it is checked automatically or by a reviewer, the features by which the parser recognises it and the JSON Schema of its body |
| `core.exercise_type_compatibility` | 37 | Which type may be shown as which, and whether the target is harder. This is what lets the system raise the difficulty of an exercise without a new exercise |
| `core.flag_reason` | 9 | Why the parser or a user may flag a place in a material: an example instead of an answer, several acceptable answers, text inside an image, no text layer, dependence on a previous exercise, a key answer not matched, a type not recognised, manual entry needed, reported as wrong |
| `core.error_type` | 4 | Spelling, Form, Word choice, Comprehension |
| `core.policy_version` | 1 | Version 1.0 of the data processing policy with its text. A consent refers to the version it was given to |
| `core.visual_style` | 1 | The default style. Reward styles that open with progress are part of the product and will be added by a migration once they are named |
| `core.pronunciation_variant` | 3 | British and American English, and one variant for Russian. Transcription and audio of a word are stored per variant |

Of the 32 exercise types, 25 are recognised in documents and 7 are only ways of showing an exercise that was recognised as another type: a learner who first chose an answer from the options later sees the options and types the answer, and finally types it without options. 28 types are checked automatically and 4 by a reviewer.

The text of the policy is a draft written for the project and uses a placeholder contact address in the reserved domain `example.com`. It must be reviewed by a lawyer before the product is used by real people.

## Test data

Test data are added by seven migrations, `0026`-`0029`, `0039`, `0040` and `0050`. Their changesets carry the Liquibase context `test`, so they are applied when the database is deployed for review and skipped with `--context-filter="!test"`. Each of these migrations has a rollback that removes exactly what it added.

Everything in the test data is invented. No sentence comes from a textbook, the users do not exist and their addresses are in the domain `example.com`, which is reserved for examples. All five users have the password `TestPassword1`, of which the database stores only the Argon2id hash.

After all migrations every one of the 57 tables contains rows: 100 rows in the reference tables and 176 in the others.

### The people in the test data

| User | Role | What the user is there to show |
|---|---|---|
| Anna | Teacher | A group, materials in folders, lessons, homework, a competition |
| Eva | Teacher | A second teacher of the same language; also studies on her own, which shows several roles in one account |
| Ben | Learner | A link with a teacher and his own course in the same language; a closed link next to an open one; the full history of answers and revision |
| Carla | Learner aged 14 to 17 | No consent to statistics by default; two teachers of one language; left a group and came back; no display name |
| Dan | Learner | Studies on his own; a withdrawn consent; an erasure request that awaits confirmation |

### Edge cases

The test data were written to exercise the rules of the database, not only to fill the tables. The table lists the cases and what each of them proves.

| Area | Case | What it shows |
|---|---|---|
| Consent | A learner aged 14 to 17 without consent to statistics; a withdrawn consent next to a new one | The partial unique index allows one consent in force and keeps the history |
| Links | A closed link beside an open one for the same pair; a link with a teacher and a self-directed course in the same language; a closed link with access left for 91 days | The rules of uniqueness apply to open links only; access after the end is accepted for a closed link |
| Groups | A learner who left and came back; a revoked invitation | A membership is a record with history |
| Requests | An erasure request awaiting confirmation and a cancelled one; an export that is ready and one that is not | The states of a request and the columns that stay empty until it is processed |
| Materials | A scanned PDF without a text layer; a book split into two parts, the first at the limit of 30 pages; a parsing run that timed out followed by a successful one | The statuses of processing and the numbering of parts |
| Exercises | An exercise whose type was not recognised; one whose type the author set by hand after the flag; an exercise that depends on another; an excluded exercise; one converted from another type | Flags, dependencies and the reference to the source exercise |
| Tasks | A task that is an example; a task with two gaps; a key with two accepted variants | The body of a task as described in [json-structures.md](json-structures.md) |
| Flags | All nine reasons, in the states pending, confirmed and corrected; flags on a task and on a whole exercise | "Exactly one target" and the life of a flag |
| Words | A word in two pronunciation variants; a word with a transcription and no audio; a learner without a chosen variant | Pronunciation per variant and the meaning of empty values |
| Answers | A wrong answer and a correct one on the second attempt; an answer with two gaps of which one is wrong; a free text awaiting review and a reviewed one | Results, attempts and review |
| Revision | A task scheduled per part: one gap is known, the other comes back the next day; a deferred record | Revision per part and deferral |
| Levels | A level raised by the system and one changed by a person; a scale with no data | The history of changes and the meaning of an empty level |
| Lessons and homework | A lesson still in progress; homework made of whole exercises and homework made of separate tasks; an overdue assignment | The two ways a homework is composed |
| Adaptation | A proposal without a decision and one modified by the user; a rejected item; an item added by the user | The states of a proposal |
| Competitions | A competition in a lesson with teams and one outside a lesson still in progress; practice answers and scored answers | The rule that separates the two kinds of competition |
| Statistics | An event without a topic, because the topic was private | Statistics keep nothing that describes a person |

Two cases are covered by tests and not by stored rows, because storing them would mean erasing a test user: a material retained after its owner erased the account, and the clean-up after the retention period. They are described in [database-objects.md](database-objects.md).

### Rows per table

| Block | Table | Rows |
|---|---|---|
| Users and access | `app_user` | 5 |
| Users and access | `consent` | 9 |
| Users and access | `course` | 3 |
| Users and access | `study_group` | 1 |
| Users and access | `learning_link` | 7 |
| Users and access | `group_membership` | 3 |
| Users and access | `invitation` | 2 |
| Users and access | `erasure_request` | 2 |
| Users and access | `export_request` | 2 |
| Users and access | `summary_link` | 2 |
| Users and access | `feature_toggle` | 3 |
| Users and access | `shown_tooltip` | 2 |
| Users and access | `pronunciation_choice` | 2 |
| Users and access | `learning_link_pseudonym` | 2 |
| Materials and parsing | `folder` | 2 |
| Materials and parsing | `material` | 5 |
| Materials and parsing | `parsing_run` | 5 |
| Materials and parsing | `topic` | 3 |
| Materials and parsing | `exercise` | 10 |
| Materials and parsing | `task` | 17 |
| Materials and parsing | `exercise_dependency` | 1 |
| Materials and parsing | `flag` | 10 |
| Materials and parsing | `image` | 3 |
| Materials and parsing | `presentation_item` | 3 |
| Materials and parsing | `word` | 4 |
| Materials and parsing | `word_pronunciation` | 3 |
| Materials and parsing | `task_target_word` | 1 |
| Materials and parsing | `exercise_target_word` | 3 |
| Lessons and homework | `lesson` | 2 |
| Lessons and homework | `lesson_exercise` | 2 |
| Lessons and homework | `homework` | 2 |
| Lessons and homework | `homework_assignment` | 3 |
| Lessons and homework | `homework_exercise` | 3 |
| Lessons and homework | `homework_task` | 2 |
| Practice and revision | `answer` | 13 |
| Practice and revision | `revision_record` | 5 |
| Practice and revision | `topic_priority` | 1 |
| History and level | `scale_level` | 6 |
| History and level | `level_change` | 2 |
| History and level | `oral_error` | 2 |
| History and level | `note` | 2 |
| Adaptation | `adaptation_proposal` | 2 |
| Adaptation | `adaptation_proposal_item` | 5 |
| Competitions | `competition` | 2 |
| Competitions | `competition_participation` | 3 |
| Anonymous statistics (schema stats) | `statistics_event` | 4 |

## Scenario queries

[scenario-queries.sql](scenario-queries.sql) contains fourteen queries written for stories of the product, from registration with consent to the result of a competition. Each of them runs on the test data and returns a meaningful result. Writing them was the last check of the structure: it found no missing table or column, and it found one gap in the test data, a competition without scored answers, which migration `0040` filled.
