# Database objects: views, functions, a trigger and procedures

Most of the logic of ILP lives in the application. A small part was placed in the database on purpose, in the cases where the database is the only place that can guarantee the rule: where a change must leave a trace whatever code makes it, where several tables must change together, or where the same calculation would otherwise be repeated in every query. Each object is created by its own migration, which also grants the rights to it.

| Object | Kind | Migration | In one sentence |
|---|---|---|---|
| `core.v_revision_queue` | View | `0041`, `0049` | What a learner may revise, and whether it is due today in the learner's time zone |
| `core.v_app_user_masked` | View | `0042` | Users with masked e-mail address and name |
| `core.v_note_masked` | View | `0042` | Notes without their text |
| `core.v_material_expiring` | View | `0048` | What a learner is about to lose after a teacher erased the account |
| `stats.mv_statistics_summary` | Materialized view | `0046` | Anonymous statistics by month, exercise type, scale and level |
| `core.next_revision` | Function | `0043` | The next interval and ease factor of spaced repetition |
| `core.log_level_change` with `trg_scale_level__log_level_change` | Trigger function and trigger | `0044` | Records every change of a level |
| `core.erase_personal_data` | Procedure | `0045`, `0048`, `0049` | Executes a confirmed erasure request |
| `core.purge_retained_materials` | Procedure | `0048` | Deletes retained materials whose period is over |
| `stats.refresh_statistics_summary` | Procedure | `0046` | Refreshes the summary without blocking readers |

## The revision queue

The queue of a learner for a day is the central screen of the product, and the question "what is due today" has a trap in it: today begins at a different moment for a learner in Vilnius and a learner in Lisbon. The view computes the current day in the time zone stored for the user and compares the next revision day with it, so the rule is written once instead of in every query of the application.

The view leaves out what must not be offered: records that are deferred, records of exercises that were excluded or archived, and records of closed learning links. A closed link stays in the queue only while the access left by the teacher lasts, and in that case the column `link_access_until` tells the screen until when. The daily limit of the learner is applied by the query that reads the view.

## Masked views

`core.v_app_user_masked` and `core.v_note_masked` give the reading role a way to work with users and notes without seeing personal data. They are described together with the rest of the protection in [personal-data.md](personal-data.md).

## The view of expiring materials

When a teacher erases the account, materials that learners worked with are kept for a limited time. `core.v_material_expiring` answers the question the learner would ask: what exactly will disappear and when. For every learning link it gives the material, the last day it is kept and the number of the learner's answers and revision records that will go with it.

## The statistics summary

`stats.mv_statistics_summary` aggregates the events by month, exercise type, scale and level: the number of events, of correct ones, of first attempts, of fast and slow answers, and the number of different learning links behind the group. Reports read this summary instead of the event table, which only grows.

It is a materialized view because its content changes slowly and is read often. The procedure `stats.refresh_statistics_summary` rebuilds it with `REFRESH MATERIALIZED VIEW CONCURRENTLY`, which requires the unique index `uq_mv_statistics_summary__key` and in exchange does not block readers during the refresh. Only the owner may refresh a materialized view, so the procedure runs with the rights of the owner and may be called by the application.

## The function of the next revision

Spaced repetition in ILP follows the SM-2 variant used by Anki. Every revision record holds an interval in days and an ease factor, and every answer receives one of four ratings that the system derives from correctness, time and corrections. `core.next_revision(interval, ease, rating)` returns the new pair.

| Rating | Meaning | New interval | New ease |
|---|---|---|---|
| `error` | The answer was wrong | 1 day | Minus 0.20 |
| `slow_and_changed` | Correct, but slow or corrected | Multiplied by 1.2 | Minus 0.15 |
| `moderate` | Correct, at a normal pace | Multiplied by the ease | Unchanged |
| `fast` | Correct and fast | Multiplied by the ease and by 1.3 | Plus 0.15 |

The ease never falls below 1.30. After a correct answer the interval grows by at least one day, because a one-day interval multiplied by 1.2 would otherwise round back to one day and the task would never move on. The function refuses an unknown rating and impossible input instead of returning a guess. It is declared immutable: the result depends only on the arguments.

For an interval of 10 days and an ease of 2.50 the four ratings give 1, 12, 25 and 33 days.

The calculation is in the database so that the application, a future batch job and a check written in SQL all use the same numbers.

## The trigger on a change of level

The level of a learner on each of four scales is stored in `core.scale_level`, and the history of its changes in `core.level_change`. The history feeds the progress chart and the congratulation on reaching a level, so a change without a record would be a visible error.

The trigger `trg_scale_level__log_level_change` fires after an update of the current level and inserts the record: the previous level, the new one and the moment. It does not fire when the first level is set on a scale, since there is no previous level and nothing changed, nor when the same value is written again.

The history also says who made the change, the system or a person, and a trigger cannot see who pressed a button. The application therefore states it for the transaction with `SET LOCAL ilp.changed_by = 'user'`; without this setting the change is attributed to the system. A wrong value is rejected by the check constraint of the history table.

## The procedure of erasure

`core.erase_personal_data(request)` executes one confirmed request from `core.erasure_request`: a single learning link or the whole account. What it erases, what it retains and for how long is described in [personal-data.md](personal-data.md). Three properties matter here.

It refuses anything but a confirmed request, so data cannot be erased by calling it with an arbitrary number. It contains no commit and therefore runs inside the transaction of the caller: if any step fails, nothing is erased and the request stays confirmed. And it runs with the rights of its owner, because the writing role is not allowed to update statistics events, while an erasure has to detach them from the private topics of the user. The search path of the procedure is fixed and every name in it is written with its schema, which is the standard precaution for a procedure with the rights of its owner.

## The clean-up of retained materials

`core.purge_retained_materials()` deletes the materials of erased owners whose retention period is over; their exercises, answers and revision records go with them through the foreign keys. It is meant to be called once a day by the application. The partial index `ix_material__retained_until` keeps this call cheap however many materials the system has.

## Who may use what

| Object | `ilp_read` | `ilp_write` | `ilp_admin` |
|---|---|---|---|
| `v_revision_queue`, `v_material_expiring`, `mv_statistics_summary` | Read | Read | All |
| `v_app_user_masked`, `v_note_masked` | Read | — (reads the tables themselves) | All |
| `next_revision` | Execute | Execute | Execute |
| `erase_personal_data`, `purge_retained_materials`, `refresh_statistics_summary` | — | Execute | Execute |

## How the objects were checked

Each object was tested on a database with test data, every test inside a transaction that was rolled back afterwards.

| Object | What was checked |
|---|---|
| Revision queue | A deferred record, an archived exercise and a closed link are left out; a closed link with access stays until the last day and leaves the queue the day after |
| Masked views | The reading role sees masked values and is refused when it reads the columns directly |
| Function | The four ratings from the same input give 1, 12, 25 and 33 days; the ease stops at 1.30; an unknown rating is refused |
| Trigger | A change by the system and a change by a person are recorded with the right author; the first level and an unchanged value add nothing |
| Erasure | An unconfirmed request is refused; one link is erased while the others stay; a learner with a private topic and a teacher with open links and nested folders are erased, although a plain `DELETE` fails for both; a failure injected at the last step leaves every row in place |
| Retention | Without a choice the material is kept seven days; with 0 it is erased at once; with 90 and 365 it is kept that long; 366 is refused; after the period the clean-up removes the material and the answers, and the levels remain |
| Summary | A new event appears after the refresh; the reading role may read and may not refresh |
