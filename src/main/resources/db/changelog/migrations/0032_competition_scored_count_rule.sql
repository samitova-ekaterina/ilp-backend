--liquibase formatted sql

--changeset samitava:0032-competition-scored-count-rule
-- In a lesson the scored tasks are all tasks of the exercise after the practice ones, so the count is not stored.
-- Outside a lesson the system selects the tasks itself and needs the count.
ALTER TABLE core.competition DROP CONSTRAINT ck_competition__lesson_or_matched;
ALTER TABLE core.competition ADD CONSTRAINT ck_competition__lesson_or_matched CHECK (
    (lesson_id IS NOT NULL AND exercise_id IS NOT NULL
        AND scale_id IS NULL AND cefr_level_id IS NULL AND exercise_type_id IS NULL
        AND scored_task_count IS NULL)
    OR
    (lesson_id IS NULL AND exercise_id IS NULL
        AND scale_id IS NOT NULL AND exercise_type_id IS NOT NULL
        AND scored_task_count IS NOT NULL)
);
COMMENT ON COLUMN core.competition.scored_task_count IS 'Number of scored tasks. Outside a lesson it is required, 10 by default; in a lesson it is NULL: all tasks of the exercise after the practice ones are scored.';
--rollback ALTER TABLE core.competition DROP CONSTRAINT ck_competition__lesson_or_matched;
--rollback ALTER TABLE core.competition ADD CONSTRAINT ck_competition__lesson_or_matched CHECK ((lesson_id IS NOT NULL AND exercise_id IS NOT NULL AND scale_id IS NULL AND cefr_level_id IS NULL AND exercise_type_id IS NULL) OR (lesson_id IS NULL AND exercise_id IS NULL AND scale_id IS NOT NULL AND exercise_type_id IS NOT NULL));
--rollback COMMENT ON COLUMN core.competition.scored_task_count IS 'Number of scored tasks. Outside a lesson, 10 by default; in a lesson it is NULL and derived from the exercise.';
