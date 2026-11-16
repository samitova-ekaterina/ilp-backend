--liquibase formatted sql

--changeset samitava:0044-level-change-function splitStatements:false
-- The history of level changes is written by the database, so no path in the application can change
-- a level without leaving a record. The application says who makes the change with
-- SET LOCAL ilp.changed_by = 'user'; without it the change is attributed to the system.
CREATE FUNCTION core.log_level_change() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO core.level_change (scale_level_id, previous_cefr_level_id, new_cefr_level_id, changed_at, changed_by)
    VALUES (NEW.id, OLD.current_cefr_level_id, NEW.current_cefr_level_id, now(),
            COALESCE(NULLIF(current_setting('ilp.changed_by', true), ''), 'system'));
    RETURN NULL;
END
$$;
--rollback DROP FUNCTION core.log_level_change();

--changeset samitava:0044-level-change-trigger
-- The first level set on a scale is not a change: there is no previous level to record.
CREATE TRIGGER trg_scale_level__log_level_change
    AFTER UPDATE OF current_cefr_level_id ON core.scale_level
    FOR EACH ROW
    WHEN (OLD.current_cefr_level_id IS NOT NULL
          AND NEW.current_cefr_level_id IS NOT NULL
          AND OLD.current_cefr_level_id <> NEW.current_cefr_level_id)
    EXECUTE FUNCTION core.log_level_change();
COMMENT ON FUNCTION core.log_level_change() IS 'Trigger function: records a change of the current level on a scale in core.level_change.';
--rollback DROP TRIGGER trg_scale_level__log_level_change ON core.scale_level;
