--liquibase formatted sql

--changeset samitava:0035-revision-record-part
-- Only the part answered wrongly comes back for revision, so the schedule is kept per part of a task.
ALTER TABLE core.revision_record ADD COLUMN part_id text;
ALTER TABLE core.revision_record ADD CONSTRAINT ck_revision_record__part_id_not_empty CHECK (part_id <> '');
ALTER TABLE core.revision_record DROP CONSTRAINT uq_revision_record__pair;
-- NULLS NOT DISTINCT: a task with a single part has NULL here and must still have one record per link.
ALTER TABLE core.revision_record ADD CONSTRAINT uq_revision_record__link_task_part
    UNIQUE NULLS NOT DISTINCT (learning_link_id, task_id, part_id);
COMMENT ON COLUMN core.revision_record.part_id IS 'Part of the task, the id from parts in the task body. NULL when the task has one part.';
--rollback DELETE FROM core.revision_record WHERE part_id IS NOT NULL;
--rollback ALTER TABLE core.revision_record DROP CONSTRAINT uq_revision_record__link_task_part;
--rollback ALTER TABLE core.revision_record ADD CONSTRAINT uq_revision_record__pair UNIQUE (learning_link_id, task_id);
--rollback ALTER TABLE core.revision_record DROP COLUMN part_id;
