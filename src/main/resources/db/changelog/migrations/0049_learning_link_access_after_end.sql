--liquibase formatted sql

--changeset samitava:0049-learning-link-access-until
-- When the lessons end, the teacher may let the learner go on revising what was studied for a limited time.
-- Without it, everything learned would stop being revised on the day the lessons end.
ALTER TABLE core.learning_link ADD COLUMN access_until date;
-- The date is compared in UTC so that the rule does not depend on the time zone of the session.
ALTER TABLE core.learning_link ADD CONSTRAINT ck_learning_link__access_after_end CHECK (
    access_until IS NULL
    OR (link_kind = 'with_teacher'
        AND ended_at IS NOT NULL
        AND access_until >= (ended_at AT TIME ZONE 'UTC')::date
        AND access_until <= (ended_at AT TIME ZONE 'UTC')::date + 365)
);
COMMENT ON COLUMN core.learning_link.access_until IS 'Last day the learner may go on revising the exercises of a closed link with a teacher, at most 365 days after the end. NULL when no such access is left.';
--rollback ALTER TABLE core.learning_link DROP COLUMN access_until;

--changeset samitava:0049-revision-queue-view-access
-- The new column goes last: CREATE OR REPLACE VIEW may only append columns.
CREATE OR REPLACE VIEW core.v_revision_queue AS
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
       rr.next_revision_date <= (now() AT TIME ZONE u.time_zone)::date AS is_due,
       ll.access_until       AS link_access_until
  FROM core.revision_record rr
  JOIN core.learning_link ll ON ll.id = rr.learning_link_id
  JOIN core.app_user u ON u.id = ll.learner_user_id
  JOIN core.task t ON t.id = rr.task_id
  JOIN core.exercise e ON e.id = t.exercise_id
 WHERE (ll.ended_at IS NULL OR ll.access_until >= (now() AT TIME ZONE u.time_zone)::date)
   AND e.excluded_at IS NULL
   AND e.archived_at IS NULL
   AND (rr.deferral_end_date IS NULL OR rr.deferral_end_date < (now() AT TIME ZONE u.time_zone)::date);
COMMENT ON VIEW core.v_revision_queue IS 'Revision records that are not deferred and whose exercise is neither excluded nor archived, for open learning links and for closed links whose access period is not over. is_due tells whether the record is due on the current day of the learner; link_access_until is set for a closed link.';
--rollback DROP VIEW core.v_revision_queue;
--rollback CREATE VIEW core.v_revision_queue AS SELECT rr.id AS revision_record_id, ll.id AS learning_link_id, ll.learner_user_id, e.id AS exercise_id, t.id AS task_id, rr.part_id, e.instruction_text, t.task_text, rr.next_revision_date, rr.current_interval_days, rr.ease, (now() AT TIME ZONE u.time_zone)::date AS learner_today, rr.next_revision_date <= (now() AT TIME ZONE u.time_zone)::date AS is_due FROM core.revision_record rr JOIN core.learning_link ll ON ll.id = rr.learning_link_id JOIN core.app_user u ON u.id = ll.learner_user_id JOIN core.task t ON t.id = rr.task_id JOIN core.exercise e ON e.id = t.exercise_id WHERE ll.ended_at IS NULL AND e.excluded_at IS NULL AND e.archived_at IS NULL AND (rr.deferral_end_date IS NULL OR rr.deferral_end_date < (now() AT TIME ZONE u.time_zone)::date);
--rollback COMMENT ON VIEW core.v_revision_queue IS 'Revision records of open learning links that are not deferred and whose exercise is neither excluded nor archived. is_due tells whether the record is due on the current day of the learner.';
--rollback GRANT SELECT ON core.v_revision_queue TO ilp_read, ilp_write;

--changeset samitava:0049-erase-personal-data-with-access splitStatements:false
CREATE OR REPLACE PROCEDURE core.erase_personal_data(p_erasure_request_id bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_request core.erasure_request%ROWTYPE;
    v_link core.learning_link%ROWTYPE;
    v_days integer;
BEGIN
    SELECT * INTO v_request FROM core.erasure_request WHERE id = p_erasure_request_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'erase_personal_data: request % does not exist', p_erasure_request_id;
    END IF;
    IF v_request.status <> 'confirmed' THEN
        RAISE EXCEPTION 'erase_personal_data: request % is %, only a confirmed request is executed', p_erasure_request_id, v_request.status;
    END IF;

    IF v_request.scope = 'single_link' THEN
        SELECT * INTO v_link FROM core.learning_link WHERE id = v_request.learning_link_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'erase_personal_data: request % has no learning link', p_erasure_request_id;
        END IF;
        IF v_link.link_kind = 'self_directed' THEN
            -- The course exists only for this link; deleting it removes the link with it.
            DELETE FROM core.course WHERE id = v_link.course_id;
        ELSE
            DELETE FROM core.learning_link WHERE id = v_link.id;
        END IF;
    ELSE
        IF v_request.app_user_id IS NULL THEN
            RAISE EXCEPTION 'erase_personal_data: request % has no user', p_erasure_request_id;
        END IF;
        v_days := COALESCE(v_request.material_retention_days, 7);
        -- A link with a teacher may lose the teacher only when it is closed. The learner keeps
        -- working with what was already studied for as long as the materials are kept.
        UPDATE core.learning_link
           SET ended_at = now(),
               access_until = CASE WHEN v_days > 0 THEN (now() AT TIME ZONE 'UTC')::date + v_days END
         WHERE teacher_user_id = v_request.app_user_id AND ended_at IS NULL;
        -- A material other people worked with stays without an owner for the chosen number of days.
        -- "Worked with" means an answer or a revision record of somebody else's learning link.
        IF v_days > 0 THEN
            UPDATE core.material m
               SET owner_user_id = NULL, retained_until = current_date + v_days, folder_id = NULL
             WHERE m.owner_user_id = v_request.app_user_id
               AND EXISTS (
                   SELECT 1
                     FROM core.parsing_run pr
                     JOIN core.exercise e ON e.parsing_run_id = pr.id
                     JOIN core.task t ON t.exercise_id = e.id
                    WHERE pr.material_id = m.id
                      AND (EXISTS (SELECT 1 FROM core.answer a
                                     JOIN core.learning_link ll ON ll.id = a.learning_link_id
                                    WHERE a.task_id = t.id AND ll.learner_user_id <> v_request.app_user_id)
                           OR EXISTS (SELECT 1 FROM core.revision_record rr
                                        JOIN core.learning_link ll ON ll.id = rr.learning_link_id
                                       WHERE rr.task_id = t.id AND ll.learner_user_id <> v_request.app_user_id)));
        END IF;
        -- The other materials go first: their exercises are the main users of the topics of the user.
        DELETE FROM core.material WHERE owner_user_id = v_request.app_user_id;
        -- What still points to a topic of the user keeps existing without the topic.
        UPDATE core.exercise SET topic_id = NULL
         WHERE topic_id IN (SELECT id FROM core.topic WHERE owner_user_id = v_request.app_user_id);
        UPDATE stats.statistics_event SET topic_id = NULL
         WHERE topic_id IN (SELECT id FROM core.topic WHERE owner_user_id = v_request.app_user_id);
        -- Folders from the leaves up: a folder with subfolders cannot be deleted.
        LOOP
            DELETE FROM core.folder f
             WHERE f.owner_user_id = v_request.app_user_id
               AND NOT EXISTS (SELECT 1 FROM core.folder c WHERE c.parent_folder_id = f.id);
            EXIT WHEN NOT FOUND;
        END LOOP;
        DELETE FROM core.app_user WHERE id = v_request.app_user_id;
    END IF;

    UPDATE core.erasure_request
       SET status = 'executed', confirmation_code_hash = NULL
     WHERE id = p_erasure_request_id;
END
$$;
--rollback CREATE OR REPLACE PROCEDURE core.erase_personal_data(p_erasure_request_id bigint)
--rollback LANGUAGE plpgsql
--rollback SECURITY DEFINER
--rollback SET search_path = pg_catalog, pg_temp
--rollback AS $$
--rollback DECLARE
--rollback     v_request core.erasure_request%ROWTYPE;
--rollback     v_link core.learning_link%ROWTYPE;
--rollback     v_days integer;
--rollback BEGIN
--rollback     SELECT * INTO v_request FROM core.erasure_request WHERE id = p_erasure_request_id FOR UPDATE;
--rollback     IF NOT FOUND THEN
--rollback         RAISE EXCEPTION 'erase_personal_data: request % does not exist', p_erasure_request_id;
--rollback     END IF;
--rollback     IF v_request.status <> 'confirmed' THEN
--rollback         RAISE EXCEPTION 'erase_personal_data: request % is %, only a confirmed request is executed', p_erasure_request_id, v_request.status;
--rollback     END IF;
--rollback
--rollback     IF v_request.scope = 'single_link' THEN
--rollback         SELECT * INTO v_link FROM core.learning_link WHERE id = v_request.learning_link_id;
--rollback         IF NOT FOUND THEN
--rollback             RAISE EXCEPTION 'erase_personal_data: request % has no learning link', p_erasure_request_id;
--rollback         END IF;
--rollback         IF v_link.link_kind = 'self_directed' THEN
--rollback             -- The course exists only for this link; deleting it removes the link with it.
--rollback             DELETE FROM core.course WHERE id = v_link.course_id;
--rollback         ELSE
--rollback             DELETE FROM core.learning_link WHERE id = v_link.id;
--rollback         END IF;
--rollback     ELSE
--rollback         IF v_request.app_user_id IS NULL THEN
--rollback             RAISE EXCEPTION 'erase_personal_data: request % has no user', p_erasure_request_id;
--rollback         END IF;
--rollback         v_days := COALESCE(v_request.material_retention_days, 7);
--rollback         -- A link with a teacher may lose the teacher only when it is closed.
--rollback         UPDATE core.learning_link SET ended_at = now()
--rollback          WHERE teacher_user_id = v_request.app_user_id AND ended_at IS NULL;
--rollback         -- A material other people worked with stays without an owner for the chosen number of days.
--rollback         -- "Worked with" means an answer or a revision record of somebody else's learning link.
--rollback         IF v_days > 0 THEN
--rollback             UPDATE core.material m
--rollback                SET owner_user_id = NULL, retained_until = current_date + v_days, folder_id = NULL
--rollback              WHERE m.owner_user_id = v_request.app_user_id
--rollback                AND EXISTS (
--rollback                    SELECT 1
--rollback                      FROM core.parsing_run pr
--rollback                      JOIN core.exercise e ON e.parsing_run_id = pr.id
--rollback                      JOIN core.task t ON t.exercise_id = e.id
--rollback                     WHERE pr.material_id = m.id
--rollback                       AND (EXISTS (SELECT 1 FROM core.answer a
--rollback                                      JOIN core.learning_link ll ON ll.id = a.learning_link_id
--rollback                                     WHERE a.task_id = t.id AND ll.learner_user_id <> v_request.app_user_id)
--rollback                            OR EXISTS (SELECT 1 FROM core.revision_record rr
--rollback                                         JOIN core.learning_link ll ON ll.id = rr.learning_link_id
--rollback                                        WHERE rr.task_id = t.id AND ll.learner_user_id <> v_request.app_user_id)));
--rollback         END IF;
--rollback         -- The other materials go first: their exercises are the main users of the topics of the user.
--rollback         DELETE FROM core.material WHERE owner_user_id = v_request.app_user_id;
--rollback         -- What still points to a topic of the user keeps existing without the topic.
--rollback         UPDATE core.exercise SET topic_id = NULL
--rollback          WHERE topic_id IN (SELECT id FROM core.topic WHERE owner_user_id = v_request.app_user_id);
--rollback         UPDATE stats.statistics_event SET topic_id = NULL
--rollback          WHERE topic_id IN (SELECT id FROM core.topic WHERE owner_user_id = v_request.app_user_id);
--rollback         -- Folders from the leaves up: a folder with subfolders cannot be deleted.
--rollback         LOOP
--rollback             DELETE FROM core.folder f
--rollback              WHERE f.owner_user_id = v_request.app_user_id
--rollback                AND NOT EXISTS (SELECT 1 FROM core.folder c WHERE c.parent_folder_id = f.id);
--rollback             EXIT WHEN NOT FOUND;
--rollback         END LOOP;
--rollback         DELETE FROM core.app_user WHERE id = v_request.app_user_id;
--rollback     END IF;
--rollback
--rollback     UPDATE core.erasure_request
--rollback        SET status = 'executed', confirmation_code_hash = NULL
--rollback      WHERE id = p_erasure_request_id;
--rollback END
--rollback $$;
