# Indexes

An index makes reading faster and writing slower: every insert, update and delete has to maintain every index of the table. An index that no query uses is therefore pure cost. The indexes of this database were chosen by two rules only, and a third rule says what was left out.

## The rules

| Rule | Reason |
|---|---|
| A foreign key that points to a working table gets an index | These columns are what queries join on, and they are what the database searches when a parent row is deleted. Without the index, deleting a material or a learning link would read every child table from beginning to end |
| A frequent query of the product that filters or sorts by other columns gets an index of its own | Each such index is tied to a named scenario |
| A foreign key that points to a reference table gets no index | A reference table has from 2 to 32 rows and its rows are never deleted. A column with a handful of distinct values narrows a search very little, while its index would still be maintained on every write |

No index was added "just in case" on text, dates or flags.

## The count

| What | How many |
|---|---|
| Foreign keys in the database | 119 |
| Already served by the index of a primary key or a unique constraint whose first column is the foreign key | 22 |
| Indexed by an `ix_` index | 66 |
| Left without an index on purpose: references to reference tables | 31 |
| Indexes for queries | 5 |
| All `ix_` indexes | 70 |

A check against the catalogue confirms that no foreign key to a working table is left without an index and that no `ix_` index repeats an index that already exists.

## Indexes for queries

| Index | Table and columns | The query it serves |
|---|---|---|
| `ix_answer__learning_link_answered_at` | `core.answer (learning_link_id, answered_at)` | The history of answers of a learning link in time order; the latest answers for the level and for adaptation. Also serves the foreign key to the learning link, so no separate index on that column exists |
| `ix_material__retained_until` | `core.material (retained_until) WHERE (retained_until IS NOT NULL)` | The daily clean-up of retained materials. A partial index: it contains only the few materials that wait for deletion |
| `ix_revision_record__link_next_date` | `core.revision_record (learning_link_id, next_revision_date)` | The revision queue of a learner for a day |
| `ix_statistics_event__event_date` | `stats.statistics_event (event_date)` | Statistics for a period |
| `ix_statistics_event__link_code` | `stats.statistics_event (link_code)` | The events of one anonymous learning link; counting how many links stand behind a figure |

## The cost on the busiest table

The table with the most indexes is `core.answer`: six, five of them added for performance. It is also the table that is written most often, one row per action of a learner, and read most often: on every opening of the history, for every calculation of a level and for adaptation. For a table written once per human action and read many times, this ratio is accepted. The other tables have from two to five indexes.

## What can and cannot be claimed

The test data contain tens of rows. On tables of that size PostgreSQL reads the whole table and ignores the indexes, and it is right to do so. No measurement on these data could prove that an index helps, so none is offered: the justification above is reasoning from the queries and the relationships. What was checked is that the indexes are usable. With sequential scans switched off, the scenario queries in [scenario-queries.sql](scenario-queries.sql) are answered through them, for example the history of answers through `ix_answer__learning_link_answered_at` and the statistics for a period through `ix_statistics_event__event_date`.

Indexes are the part of a database most worth revisiting with real data. When the system has a real load, the usage statistics of PostgreSQL will show which of these indexes are never read, and those can be dropped by a migration.

## Indexes of foreign keys

| Table | Index | Column | Refers to |
|---|---|---|---|
| `core.adaptation_proposal` | `ix_adaptation_proposal__learning_link` | `learning_link_id` | `core.learning_link` |
| `core.adaptation_proposal_item` | `ix_adaptation_proposal_item__exercise` | `exercise_id` | `core.exercise` |
| `core.adaptation_proposal_item` | `ix_adaptation_proposal_item__rationale_topic` | `rationale_topic_id` | `core.topic` |
| `core.answer` | `ix_answer__competition_participation` | `competition_participation_id` | `core.competition_participation` |
| `core.answer` | `ix_answer__homework_assignment` | `homework_assignment_id` | `core.homework_assignment` |
| `core.answer` | `ix_answer__lesson_exercise` | `lesson_exercise_id` | `core.lesson_exercise` |
| `core.answer` | `ix_answer__task` | `task_id` | `core.task` |
| `core.competition` | `ix_competition__exercise` | `exercise_id` | `core.exercise` |
| `core.competition` | `ix_competition__lesson` | `lesson_id` | `core.lesson` |
| `core.competition_participation` | `ix_competition_participation__learning_link` | `learning_link_id` | `core.learning_link` |
| `core.consent` | `ix_consent__app_user` | `app_user_id` | `core.app_user` |
| `core.course` | `ix_course__owner_user` | `owner_user_id` | `core.app_user` |
| `core.erasure_request` | `ix_erasure_request__app_user` | `app_user_id` | `core.app_user` |
| `core.erasure_request` | `ix_erasure_request__learning_link` | `learning_link_id` | `core.learning_link` |
| `core.exercise` | `ix_exercise__parsing_run` | `parsing_run_id` | `core.parsing_run` |
| `core.exercise` | `ix_exercise__source_exercise` | `source_exercise_id` | `core.exercise` |
| `core.exercise` | `ix_exercise__topic` | `topic_id` | `core.topic` |
| `core.exercise_dependency` | `ix_exercise_dependency__prerequisite_exercise` | `prerequisite_exercise_id` | `core.exercise` |
| `core.exercise_target_word` | `ix_exercise_target_word__word` | `word_id` | `core.word` |
| `core.export_request` | `ix_export_request__app_user` | `app_user_id` | `core.app_user` |
| `core.export_request` | `ix_export_request__learning_link` | `learning_link_id` | `core.learning_link` |
| `core.flag` | `ix_flag__exercise` | `exercise_id` | `core.exercise` |
| `core.flag` | `ix_flag__placed_by_user` | `placed_by_user_id` | `core.app_user` |
| `core.flag` | `ix_flag__task` | `task_id` | `core.task` |
| `core.folder` | `ix_folder__owner_user` | `owner_user_id` | `core.app_user` |
| `core.folder` | `ix_folder__parent_folder` | `parent_folder_id` | `core.folder` |
| `core.group_membership` | `ix_group_membership__learning_link` | `learning_link_id` | `core.learning_link` |
| `core.group_membership` | `ix_group_membership__study_group` | `study_group_id` | `core.study_group` |
| `core.homework` | `ix_homework__adaptation_proposal` | `adaptation_proposal_id` | `core.adaptation_proposal` |
| `core.homework` | `ix_homework__assigned_by_user` | `assigned_by_user_id` | `core.app_user` |
| `core.homework` | `ix_homework__study_group` | `study_group_id` | `core.study_group` |
| `core.homework_assignment` | `ix_homework_assignment__learning_link` | `learning_link_id` | `core.learning_link` |
| `core.homework_exercise` | `ix_homework_exercise__exercise` | `exercise_id` | `core.exercise` |
| `core.homework_task` | `ix_homework_task__task` | `task_id` | `core.task` |
| `core.image` | `ix_image__exercise` | `exercise_id` | `core.exercise` |
| `core.image` | `ix_image__source_image` | `source_image_id` | `core.image` |
| `core.image` | `ix_image__task` | `task_id` | `core.task` |
| `core.invitation` | `ix_invitation__study_group` | `study_group_id` | `core.study_group` |
| `core.learning_link` | `ix_learning_link__learner_user` | `learner_user_id` | `core.app_user` |
| `core.learning_link` | `ix_learning_link__teacher_user` | `teacher_user_id` | `core.app_user` |
| `core.lesson` | `ix_lesson__learning_link` | `learning_link_id` | `core.learning_link` |
| `core.lesson` | `ix_lesson__study_group` | `study_group_id` | `core.study_group` |
| `core.lesson_exercise` | `ix_lesson_exercise__exercise` | `exercise_id` | `core.exercise` |
| `core.lesson_exercise` | `ix_lesson_exercise__lesson` | `lesson_id` | `core.lesson` |
| `core.lesson_exercise` | `ix_lesson_exercise__shown_to_learning_link` | `shown_to_learning_link_id` | `core.learning_link` |
| `core.level_change` | `ix_level_change__scale_level` | `scale_level_id` | `core.scale_level` |
| `core.material` | `ix_material__course` | `course_id` | `core.course` |
| `core.material` | `ix_material__folder` | `folder_id` | `core.folder` |
| `core.material` | `ix_material__owner_user` | `owner_user_id` | `core.app_user` |
| `core.note` | `ix_note__learning_link` | `learning_link_id` | `core.learning_link` |
| `core.note` | `ix_note__lesson` | `lesson_id` | `core.lesson` |
| `core.oral_error` | `ix_oral_error__learning_link` | `learning_link_id` | `core.learning_link` |
| `core.oral_error` | `ix_oral_error__lesson` | `lesson_id` | `core.lesson` |
| `core.oral_error` | `ix_oral_error__task` | `task_id` | `core.task` |
| `core.oral_error` | `ix_oral_error__topic` | `topic_id` | `core.topic` |
| `core.parsing_run` | `ix_parsing_run__material` | `material_id` | `core.material` |
| `core.presentation_item` | `ix_presentation_item__exercise` | `exercise_id` | `core.exercise` |
| `core.presentation_item` | `ix_presentation_item__task` | `task_id` | `core.task` |
| `core.revision_record` | `ix_revision_record__task` | `task_id` | `core.task` |
| `stats.statistics_event` | `ix_statistics_event__topic` | `topic_id` | `core.topic` |
| `core.study_group` | `ix_study_group__teacher_user` | `teacher_user_id` | `core.app_user` |
| `core.summary_link` | `ix_summary_link__learning_link` | `learning_link_id` | `core.learning_link` |
| `core.task_target_word` | `ix_task_target_word__word` | `word_id` | `core.word` |
| `core.topic_priority` | `ix_topic_priority__learning_link` | `learning_link_id` | `core.learning_link` |
| `core.topic_priority` | `ix_topic_priority__topic` | `topic_id` | `core.topic` |
