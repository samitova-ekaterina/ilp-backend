--liquibase formatted sql

--changeset samitava:0045-erase-personal-data-procedure splitStatements:false
-- Runs inside the transaction of the caller: either everything is erased or nothing.
-- SECURITY DEFINER because the writing role may only insert into the statistics, and the erasure
-- has to detach the statistics from the topics of the user.
CREATE PROCEDURE core.erase_personal_data(p_erasure_request_id bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_request core.erasure_request%ROWTYPE;
    v_link core.learning_link%ROWTYPE;
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
        -- A link with a teacher may lose the teacher only when it is closed.
        UPDATE core.learning_link SET ended_at = now()
         WHERE teacher_user_id = v_request.app_user_id AND ended_at IS NULL;
        -- Materials first: their exercises are the main users of the topics of the user.
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
--rollback DROP PROCEDURE core.erase_personal_data(bigint);

--changeset samitava:0045-erase-personal-data-privileges
COMMENT ON PROCEDURE core.erase_personal_data(bigint) IS 'Executes a confirmed erasure request: one learning link or the whole account. The anonymous statistics stay; the table that links them to a learning link is erased with the link.';
REVOKE ALL ON PROCEDURE core.erase_personal_data(bigint) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE core.erase_personal_data(bigint) TO ilp_write, ilp_admin;
--rollback REVOKE ALL ON PROCEDURE core.erase_personal_data(bigint) FROM ilp_write, ilp_admin;
