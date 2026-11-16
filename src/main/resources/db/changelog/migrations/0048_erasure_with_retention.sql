--liquibase formatted sql

--changeset samitava:0048-erase-personal-data-with-retention splitStatements:false
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
        -- A link with a teacher may lose the teacher only when it is closed.
        UPDATE core.learning_link SET ended_at = now()
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
--rollback         -- A link with a teacher may lose the teacher only when it is closed.
--rollback         UPDATE core.learning_link SET ended_at = now()
--rollback          WHERE teacher_user_id = v_request.app_user_id AND ended_at IS NULL;
--rollback         -- Materials first: their exercises are the main users of the topics of the user.
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

--changeset samitava:0048-purge-retained-materials splitStatements:false
CREATE PROCEDURE core.purge_retained_materials()
LANGUAGE plpgsql
AS $$
BEGIN
    -- Exercises, answers and revision records of these materials go with them.
    DELETE FROM core.material WHERE retained_until < current_date;
END
$$;
--rollback DROP PROCEDURE core.purge_retained_materials();

--changeset samitava:0048-purge-retained-materials-privileges
COMMENT ON PROCEDURE core.purge_retained_materials() IS 'Deletes the materials of erased owners whose retention period is over. Meant to be called once a day.';
COMMENT ON PROCEDURE core.erase_personal_data(bigint) IS 'Executes a confirmed erasure request: one learning link or the whole account. Materials other people worked with stay without an owner for material_retention_days (7 by default). The anonymous statistics stay; the table that links them to a learning link is erased with the link.';
REVOKE ALL ON PROCEDURE core.purge_retained_materials() FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE core.purge_retained_materials() TO ilp_write, ilp_admin;
--rollback REVOKE ALL ON PROCEDURE core.purge_retained_materials() FROM ilp_write, ilp_admin;
--rollback COMMENT ON PROCEDURE core.erase_personal_data(bigint) IS 'Executes a confirmed erasure request: one learning link or the whole account. The anonymous statistics stay; the table that links them to a learning link is erased with the link.';

--changeset samitava:0048-expiring-material-view
-- What a learner is about to lose: shown before it happens, not after.
CREATE VIEW core.v_material_expiring AS
WITH answered AS (
    SELECT a.learning_link_id, pr.material_id, count(*) AS answers
      FROM core.answer a
      JOIN core.task t ON t.id = a.task_id
      JOIN core.exercise e ON e.id = t.exercise_id
      JOIN core.parsing_run pr ON pr.id = e.parsing_run_id
     GROUP BY a.learning_link_id, pr.material_id
), revised AS (
    SELECT rr.learning_link_id, pr.material_id, count(*) AS revision_records
      FROM core.revision_record rr
      JOIN core.task t ON t.id = rr.task_id
      JOIN core.exercise e ON e.id = t.exercise_id
      JOIN core.parsing_run pr ON pr.id = e.parsing_run_id
     GROUP BY rr.learning_link_id, pr.material_id
)
SELECT ll.id AS learning_link_id,
       ll.learner_user_id,
       m.id AS material_id,
       m.name AS material_name,
       m.retained_until,
       COALESCE(x.answers, 0) AS answers,
       COALESCE(x.revision_records, 0) AS revision_records
  FROM (SELECT learning_link_id, material_id, answers, revision_records
          FROM answered FULL JOIN revised USING (learning_link_id, material_id)) x
  JOIN core.material m ON m.id = x.material_id
  JOIN core.learning_link ll ON ll.id = x.learning_link_id
 WHERE m.retained_until IS NOT NULL;
COMMENT ON VIEW core.v_material_expiring IS 'For every learning link: materials of erased owners that will be deleted, the day until which they are kept and how many answers and revision records of the link go with them.';
GRANT SELECT ON core.v_material_expiring TO ilp_read, ilp_write;
--rollback DROP VIEW core.v_material_expiring;
