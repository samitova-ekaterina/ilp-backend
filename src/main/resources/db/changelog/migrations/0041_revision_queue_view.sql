--liquibase formatted sql

--changeset samitava:0041-revision-queue-view
-- The day of a learner starts in the learner's own time zone, so "due today" is computed here once
-- instead of in every query of the application.
CREATE VIEW core.v_revision_queue AS
SELECT rr.id                 AS revision_record_id,
       ll.id                 AS learning_link_id,
       ll.learner_user_id,
       e.id                  AS exercise_id,
       t.id                  AS task_id,
       rr.part_id,
       e.instruction_text,
       t.task_text,
       rr.next_revision_date,
       rr.current_interval_days,
       rr.ease,
       (now() AT TIME ZONE u.time_zone)::date AS learner_today,
       rr.next_revision_date <= (now() AT TIME ZONE u.time_zone)::date AS is_due
  FROM core.revision_record rr
  JOIN core.learning_link ll ON ll.id = rr.learning_link_id
  JOIN core.app_user u ON u.id = ll.learner_user_id
  JOIN core.task t ON t.id = rr.task_id
  JOIN core.exercise e ON e.id = t.exercise_id
 WHERE ll.ended_at IS NULL
   AND e.excluded_at IS NULL
   AND e.archived_at IS NULL
   AND (rr.deferral_end_date IS NULL OR rr.deferral_end_date < (now() AT TIME ZONE u.time_zone)::date);
COMMENT ON VIEW core.v_revision_queue IS 'Revision records of open learning links that are not deferred and whose exercise is neither excluded nor archived. is_due tells whether the record is due on the current day of the learner.';
GRANT SELECT ON core.v_revision_queue TO ilp_read, ilp_write;
--rollback DROP VIEW core.v_revision_queue;
