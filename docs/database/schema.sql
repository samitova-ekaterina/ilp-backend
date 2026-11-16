--
-- PostgreSQL database dump
--

-- Dumped from database version 17.5
-- Dumped by pg_dump version 17.5

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: core; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA core;


--
-- Name: SCHEMA core; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA core IS 'Main application data.';


--
-- Name: stats; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA stats;


--
-- Name: SCHEMA stats; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA stats IS 'Anonymised usage statistics. Contains no personal data.';


--
-- Name: erase_personal_data(bigint); Type: PROCEDURE; Schema: core; Owner: -
--

CREATE PROCEDURE core.erase_personal_data(IN p_erasure_request_id bigint)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'pg_temp'
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
            
            DELETE FROM core.course WHERE id = v_link.course_id;
        ELSE
            DELETE FROM core.learning_link WHERE id = v_link.id;
        END IF;
    ELSE
        IF v_request.app_user_id IS NULL THEN
            RAISE EXCEPTION 'erase_personal_data: request % has no user', p_erasure_request_id;
        END IF;
        v_days := COALESCE(v_request.material_retention_days, 7);
        
        
        UPDATE core.learning_link
           SET ended_at = now(),
               access_until = CASE WHEN v_days > 0 THEN (now() AT TIME ZONE 'UTC')::date + v_days END
         WHERE teacher_user_id = v_request.app_user_id AND ended_at IS NULL;
        
        
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
        
        DELETE FROM core.material WHERE owner_user_id = v_request.app_user_id;
        
        UPDATE core.exercise SET topic_id = NULL
         WHERE topic_id IN (SELECT id FROM core.topic WHERE owner_user_id = v_request.app_user_id);
        UPDATE stats.statistics_event SET topic_id = NULL
         WHERE topic_id IN (SELECT id FROM core.topic WHERE owner_user_id = v_request.app_user_id);
        
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


--
-- Name: PROCEDURE erase_personal_data(IN p_erasure_request_id bigint); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON PROCEDURE core.erase_personal_data(IN p_erasure_request_id bigint) IS 'Executes a confirmed erasure request: one learning link or the whole account. Materials other people worked with stay without an owner for material_retention_days (7 by default). The anonymous statistics stay; the table that links them to a learning link is erased with the link.';


--
-- Name: log_level_change(); Type: FUNCTION; Schema: core; Owner: -
--

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


--
-- Name: FUNCTION log_level_change(); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.log_level_change() IS 'Trigger function: records a change of the current level on a scale in core.level_change.';


--
-- Name: next_revision(integer, numeric, text); Type: FUNCTION; Schema: core; Owner: -
--

CREATE FUNCTION core.next_revision(p_interval_days integer, p_ease numeric, p_rating text) RETURNS TABLE(new_interval_days integer, new_ease numeric)
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    IF p_interval_days IS NULL OR p_interval_days < 1 OR p_ease IS NULL OR p_ease < 1.30 THEN
        RAISE EXCEPTION 'next_revision: interval must be at least 1 and ease at least 1.30, got % and %', p_interval_days, p_ease;
    END IF;
    CASE p_rating
        WHEN 'error' THEN
            new_interval_days := 1;
            new_ease := greatest(1.30, p_ease - 0.20);
        WHEN 'slow_and_changed' THEN
            new_interval_days := greatest(p_interval_days + 1, round(p_interval_days * 1.2)::integer);
            new_ease := greatest(1.30, p_ease - 0.15);
        WHEN 'moderate' THEN
            new_interval_days := greatest(p_interval_days + 1, round(p_interval_days * p_ease)::integer);
            new_ease := p_ease;
        WHEN 'fast' THEN
            new_interval_days := greatest(p_interval_days + 1, round(p_interval_days * p_ease * 1.3)::integer);
            new_ease := p_ease + 0.15;
        ELSE
            RAISE EXCEPTION 'next_revision: unknown rating %', p_rating;
    END CASE;
    RETURN NEXT;
END
$$;


--
-- Name: FUNCTION next_revision(p_interval_days integer, p_ease numeric, p_rating text); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON FUNCTION core.next_revision(p_interval_days integer, p_ease numeric, p_rating text) IS 'New interval in days and new ease of a revision record after an answer with the given rating: error, slow_and_changed, moderate or fast.';


--
-- Name: purge_retained_materials(); Type: PROCEDURE; Schema: core; Owner: -
--

CREATE PROCEDURE core.purge_retained_materials()
    LANGUAGE plpgsql
    AS $$
BEGIN
    
    DELETE FROM core.material WHERE retained_until < current_date;
END
$$;


--
-- Name: PROCEDURE purge_retained_materials(); Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON PROCEDURE core.purge_retained_materials() IS 'Deletes the materials of erased owners whose retention period is over. Meant to be called once a day.';


--
-- Name: refresh_statistics_summary(); Type: PROCEDURE; Schema: stats; Owner: -
--

CREATE PROCEDURE stats.refresh_statistics_summary()
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'pg_temp'
    AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY stats.mv_statistics_summary;
END
$$;


--
-- Name: PROCEDURE refresh_statistics_summary(); Type: COMMENT; Schema: stats; Owner: -
--

COMMENT ON PROCEDURE stats.refresh_statistics_summary() IS 'Refreshes stats.mv_statistics_summary without blocking readers.';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: adaptation_proposal; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.adaptation_proposal (
    id bigint NOT NULL,
    learning_link_id bigint NOT NULL,
    generated_at timestamp with time zone NOT NULL,
    status text NOT NULL,
    decided_by text,
    decided_at timestamp with time zone,
    CONSTRAINT ck_adaptation_proposal__decided_by CHECK ((decided_by = ANY (ARRAY['system'::text, 'user'::text]))),
    CONSTRAINT ck_adaptation_proposal__decision_complete CHECK (((decided_by IS NULL) = (decided_at IS NULL))),
    CONSTRAINT ck_adaptation_proposal__status CHECK ((status = ANY (ARRAY['proposed'::text, 'approved'::text, 'modified'::text, 'assigned'::text]))),
    CONSTRAINT ck_adaptation_proposal__status_matches_decision CHECK (((status = 'proposed'::text) = (decided_by IS NULL)))
);


--
-- Name: TABLE adaptation_proposal; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.adaptation_proposal IS 'Proposal of what to do next for a learner. Nothing is assigned until a decision is made.';


--
-- Name: COLUMN adaptation_proposal.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.adaptation_proposal.id IS 'Surrogate key.';


--
-- Name: COLUMN adaptation_proposal.learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.adaptation_proposal.learning_link_id IS 'Learning link the proposal is built for.';


--
-- Name: COLUMN adaptation_proposal.generated_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.adaptation_proposal.generated_at IS 'Moment the proposal was generated.';


--
-- Name: COLUMN adaptation_proposal.status; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.adaptation_proposal.status IS 'Status: proposed, approved, modified or assigned.';


--
-- Name: COLUMN adaptation_proposal.decided_by; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.adaptation_proposal.decided_by IS 'Who made the decision: system or user. NULL until a decision is made.';


--
-- Name: COLUMN adaptation_proposal.decided_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.adaptation_proposal.decided_at IS 'Moment of the decision. NULL until a decision is made.';


--
-- Name: adaptation_proposal_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.adaptation_proposal ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.adaptation_proposal_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: adaptation_proposal_item; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.adaptation_proposal_item (
    id bigint NOT NULL,
    adaptation_proposal_id bigint NOT NULL,
    item_kind text NOT NULL,
    exercise_id bigint NOT NULL,
    rationale_topic_id bigint,
    rationale_period_from date,
    rationale_period_to date,
    added_by text NOT NULL,
    is_accepted boolean DEFAULT true NOT NULL,
    shown_as_exercise_type_id bigint,
    CONSTRAINT ck_adaptation_proposal_item__added_by CHECK ((added_by = ANY (ARRAY['system'::text, 'user'::text]))),
    CONSTRAINT ck_adaptation_proposal_item__item_kind CHECK ((item_kind = ANY (ARRAY['give_next'::text, 'return_to_revision'::text, 'make_easier'::text, 'make_harder'::text]))),
    CONSTRAINT ck_adaptation_proposal_item__period CHECK ((((rationale_period_from IS NULL) AND (rationale_period_to IS NULL)) OR (rationale_period_from <= rationale_period_to))),
    CONSTRAINT ck_adaptation_proposal_item__shown_type_only_for_change CHECK (((shown_as_exercise_type_id IS NULL) OR (item_kind = ANY (ARRAY['make_easier'::text, 'make_harder'::text])))),
    CONSTRAINT ck_adaptation_proposal_item__system_has_rationale CHECK (((added_by <> 'system'::text) OR (rationale_period_from IS NOT NULL)))
);


--
-- Name: TABLE adaptation_proposal_item; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.adaptation_proposal_item IS 'One item of an adaptation proposal: an exercise and what to do with it.';


--
-- Name: COLUMN adaptation_proposal_item.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.adaptation_proposal_item.id IS 'Surrogate key.';


--
-- Name: COLUMN adaptation_proposal_item.adaptation_proposal_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.adaptation_proposal_item.adaptation_proposal_id IS 'Proposal the item belongs to.';


--
-- Name: COLUMN adaptation_proposal_item.item_kind; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.adaptation_proposal_item.item_kind IS 'Kind: give_next, return_to_revision, make_easier or make_harder.';


--
-- Name: COLUMN adaptation_proposal_item.exercise_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.adaptation_proposal_item.exercise_id IS 'Exercise the item is about.';


--
-- Name: COLUMN adaptation_proposal_item.rationale_topic_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.adaptation_proposal_item.rationale_topic_id IS 'Topic the rationale is based on. NULL for an item added by a user.';


--
-- Name: COLUMN adaptation_proposal_item.rationale_period_from; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.adaptation_proposal_item.rationale_period_from IS 'Start of the period the rationale is based on. NULL for an item added by a user.';


--
-- Name: COLUMN adaptation_proposal_item.rationale_period_to; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.adaptation_proposal_item.rationale_period_to IS 'End of the period the rationale is based on. NULL for an item added by a user.';


--
-- Name: COLUMN adaptation_proposal_item.added_by; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.adaptation_proposal_item.added_by IS 'Who added the item: system or user.';


--
-- Name: COLUMN adaptation_proposal_item.is_accepted; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.adaptation_proposal_item.is_accepted IS 'False when the user rejected the item. A rejected item stays in the record but is not given to the learner.';


--
-- Name: COLUMN adaptation_proposal_item.shown_as_exercise_type_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.adaptation_proposal_item.shown_as_exercise_type_id IS 'Exercise type the exercise is shown in. Filled only for make_easier and make_harder.';


--
-- Name: adaptation_proposal_item_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.adaptation_proposal_item ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.adaptation_proposal_item_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: answer; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.answer (
    id bigint NOT NULL,
    task_id bigint NOT NULL,
    learning_link_id bigint NOT NULL,
    homework_assignment_id bigint,
    content jsonb NOT NULL,
    result text NOT NULL,
    attempt_number integer NOT NULL,
    response_time_ms integer NOT NULL,
    active_time_ms integer NOT NULL,
    answered_at timestamp with time zone NOT NULL,
    answer_change_count integer DEFAULT 0 NOT NULL,
    answer_rating text,
    lesson_exercise_id bigint,
    error_type_id bigint,
    competition_participation_id bigint,
    shown_as_exercise_type_id bigint,
    audio_location text,
    reviewed_at timestamp with time zone,
    CONSTRAINT ck_answer__active_time_within_response CHECK ((active_time_ms <= response_time_ms)),
    CONSTRAINT ck_answer__answer_change_count_not_negative CHECK ((answer_change_count >= 0)),
    CONSTRAINT ck_answer__answer_rating CHECK ((answer_rating = ANY (ARRAY['error'::text, 'slow_and_changed'::text, 'moderate'::text, 'fast'::text]))),
    CONSTRAINT ck_answer__attempt_number_positive CHECK ((attempt_number >= 1)),
    CONSTRAINT ck_answer__response_time_not_negative CHECK ((response_time_ms >= 0)),
    CONSTRAINT ck_answer__result CHECK ((result = ANY (ARRAY['correct'::text, 'incorrect'::text, 'awaiting_review'::text])))
);


--
-- Name: TABLE answer; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.answer IS 'Answer of a learner to a task. One task can be answered many times: in a lesson, in homework, at each revision.';


--
-- Name: COLUMN answer.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.id IS 'Surrogate key.';


--
-- Name: COLUMN answer.task_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.task_id IS 'Task that was answered.';


--
-- Name: COLUMN answer.learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.learning_link_id IS 'Learning link of the learner.';


--
-- Name: COLUMN answer.homework_assignment_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.homework_assignment_id IS 'Homework the answer was given for. NULL when not given for homework.';


--
-- Name: COLUMN answer.content; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.content IS 'Content of the answer. Its structure is defined by the exercise type.';


--
-- Name: COLUMN answer.result; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.result IS 'Result: correct, incorrect or awaiting_review (to be checked by a person).';


--
-- Name: COLUMN answer.attempt_number; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.attempt_number IS 'Number of the attempt within one pass through the task.';


--
-- Name: COLUMN answer.response_time_ms; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.response_time_ms IS 'Response time in milliseconds.';


--
-- Name: COLUMN answer.active_time_ms; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.active_time_ms IS 'Active time in milliseconds: response time without long pauses.';


--
-- Name: COLUMN answer.answered_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.answered_at IS 'Moment the answer was given.';


--
-- Name: COLUMN answer.answer_change_count; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.answer_change_count IS 'How many times the learner changed the answer before sending it.';


--
-- Name: COLUMN answer.answer_rating; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.answer_rating IS 'Rating derived by the system: error, slow_and_changed, moderate or fast. NULL while the answer awaits review.';


--
-- Name: COLUMN answer.lesson_exercise_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.lesson_exercise_id IS 'Showing of the exercise in a lesson during which the answer was given. NULL when not given in a lesson.';


--
-- Name: COLUMN answer.error_type_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.error_type_id IS 'Type of the mistake. NULL for a correct answer and until the type is determined.';


--
-- Name: COLUMN answer.competition_participation_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.competition_participation_id IS 'Participation in a competition within which the answer was given. NULL for an ordinary answer.';


--
-- Name: COLUMN answer.shown_as_exercise_type_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.shown_as_exercise_type_id IS 'Exercise type in which the task was shown. NULL when it was shown in the own type of the exercise.';


--
-- Name: COLUMN answer.audio_location; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.audio_location IS 'Address of the audio recording. NULL when the answer is not audio.';


--
-- Name: COLUMN answer.reviewed_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.answer.reviewed_at IS 'Moment the answer was reviewed by a person. NULL for an answer checked automatically.';


--
-- Name: answer_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.answer ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.answer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: app_user; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.app_user (
    id bigint NOT NULL,
    email text NOT NULL,
    password_hash text NOT NULL,
    country_id bigint NOT NULL,
    age_group text NOT NULL,
    registration_role text NOT NULL,
    display_name text,
    interface_language_id bigint NOT NULL,
    registered_at timestamp with time zone NOT NULL,
    time_zone text NOT NULL,
    daily_task_limit integer DEFAULT 30 NOT NULL,
    reminder_time time without time zone,
    reminders_enabled boolean DEFAULT false NOT NULL,
    last_reminder_sent_at timestamp with time zone,
    visual_style_id bigint,
    show_added_glossaries boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_app_user__age_group CHECK ((age_group = ANY (ARRAY['14-17'::text, 'adult'::text]))),
    CONSTRAINT ck_app_user__daily_task_limit_positive CHECK ((daily_task_limit > 0)),
    CONSTRAINT ck_app_user__email_lowercase CHECK ((email = lower(email))),
    CONSTRAINT ck_app_user__registration_role CHECK ((registration_role = ANY (ARRAY['teacher'::text, 'learner'::text])))
);


--
-- Name: TABLE app_user; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.app_user IS 'User account. One account can combine the roles of teacher, learner and self-directed learner.';


--
-- Name: COLUMN app_user.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.app_user.id IS 'Surrogate key.';


--
-- Name: COLUMN app_user.email; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.app_user.email IS 'Personal data. E-mail address, stored in lower case. A second registration with the same address is rejected.';


--
-- Name: COLUMN app_user.password_hash; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.app_user.password_hash IS 'Password hash. The password itself is not stored.';


--
-- Name: COLUMN app_user.country_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.app_user.country_id IS 'Country of the user.';


--
-- Name: COLUMN app_user.age_group; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.app_user.age_group IS 'Age group: 14-17 or adult. The date of birth is not stored.';


--
-- Name: COLUMN app_user.registration_role; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.app_user.registration_role IS 'Role chosen at registration: teacher or learner.';


--
-- Name: COLUMN app_user.display_name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.app_user.display_name IS 'Personal data. Name shown to other users. NULL until the user sets it.';


--
-- Name: COLUMN app_user.interface_language_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.app_user.interface_language_id IS 'Language of the user interface.';


--
-- Name: COLUMN app_user.registered_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.app_user.registered_at IS 'Moment of registration.';


--
-- Name: COLUMN app_user.time_zone; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.app_user.time_zone IS 'Full time zone name, for example Europe/Vilnius. Defines day boundaries for the queue and deadlines.';


--
-- Name: COLUMN app_user.daily_task_limit; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.app_user.daily_task_limit IS 'Maximum number of tasks in the daily queue.';


--
-- Name: COLUMN app_user.reminder_time; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.app_user.reminder_time IS 'Time of day for the reminder e-mail, in the user time zone. NULL until the user chooses a time.';


--
-- Name: COLUMN app_user.reminders_enabled; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.app_user.reminders_enabled IS 'Whether reminder e-mails are sent. Kept apart from the time so that switching off does not erase the chosen time.';


--
-- Name: COLUMN app_user.last_reminder_sent_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.app_user.last_reminder_sent_at IS 'Moment the last reminder e-mail was sent. NULL until the first one. Used to send at most one e-mail a day.';


--
-- Name: COLUMN app_user.visual_style_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.app_user.visual_style_id IS 'Visual style chosen by the user. NULL when the default style is used.';


--
-- Name: COLUMN app_user.show_added_glossaries; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.app_user.show_added_glossaries IS 'Whether glossaries added to the material are shown to the user.';


--
-- Name: app_user_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.app_user ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.app_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cefr_level; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.cefr_level (
    id bigint NOT NULL,
    name text NOT NULL,
    sort_order integer NOT NULL
);


--
-- Name: TABLE cefr_level; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.cefr_level IS 'CEFR level: A1, A2, B1 and so on.';


--
-- Name: COLUMN cefr_level.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.cefr_level.id IS 'Surrogate key.';


--
-- Name: COLUMN cefr_level.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.cefr_level.name IS 'CEFR mark, for example A1.';


--
-- Name: COLUMN cefr_level.sort_order; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.cefr_level.sort_order IS 'Ordinal number used to compare levels: higher or lower.';


--
-- Name: cefr_level_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.cefr_level ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.cefr_level_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: competition; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.competition (
    id bigint NOT NULL,
    lesson_id bigint,
    scale_id bigint,
    cefr_level_id bigint,
    exercise_type_id bigint,
    answer_time_limit_ms integer DEFAULT 240000 NOT NULL,
    started_at timestamp with time zone NOT NULL,
    ended_at timestamp with time zone,
    exercise_id bigint,
    practice_task_count integer DEFAULT 1 NOT NULL,
    scored_task_count integer,
    CONSTRAINT ck_competition__answer_time_limit_positive CHECK ((answer_time_limit_ms > 0)),
    CONSTRAINT ck_competition__ended_after_started CHECK ((ended_at >= started_at)),
    CONSTRAINT ck_competition__lesson_or_matched CHECK ((((lesson_id IS NOT NULL) AND (exercise_id IS NOT NULL) AND (scale_id IS NULL) AND (cefr_level_id IS NULL) AND (exercise_type_id IS NULL) AND (scored_task_count IS NULL)) OR ((lesson_id IS NULL) AND (exercise_id IS NULL) AND (scale_id IS NOT NULL) AND (exercise_type_id IS NOT NULL) AND (scored_task_count IS NOT NULL)))),
    CONSTRAINT ck_competition__practice_task_count_not_negative CHECK ((practice_task_count >= 0)),
    CONSTRAINT ck_competition__scored_task_count_positive CHECK ((scored_task_count > 0))
);


--
-- Name: TABLE competition; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.competition IS 'Competition: either held in a lesson on one exercise, or matched by the system among learners of equal level. Correctness is scored, not speed. The state is derived from the dates.';


--
-- Name: COLUMN competition.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition.id IS 'Surrogate key.';


--
-- Name: COLUMN competition.lesson_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition.lesson_id IS 'Lesson the competition is held in. NULL for a competition outside a lesson.';


--
-- Name: COLUMN competition.scale_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition.scale_id IS 'Scale by which equal participants are matched. Filled only outside a lesson.';


--
-- Name: COLUMN competition.cefr_level_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition.cefr_level_id IS 'Level of the participants. Only outside a lesson; NULL for a competition composed by a teacher.';


--
-- Name: COLUMN competition.exercise_type_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition.exercise_type_id IS 'Exercise type familiar to all participants. Filled only outside a lesson.';


--
-- Name: COLUMN competition.answer_time_limit_ms; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition.answer_time_limit_ms IS 'Time allowed for one answer, in milliseconds. A ceiling, not a race: there is no countdown and speed is not scored. When it expires the task counts as unanswered.';


--
-- Name: COLUMN competition.started_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition.started_at IS 'Moment the competition started.';


--
-- Name: COLUMN competition.ended_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition.ended_at IS 'Moment the competition ended. NULL while it is in progress.';


--
-- Name: COLUMN competition.exercise_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition.exercise_id IS 'Exercise the competition is held on. Filled only in a lesson.';


--
-- Name: COLUMN competition.practice_task_count; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition.practice_task_count IS 'Number of practice tasks before the scored ones.';


--
-- Name: COLUMN competition.scored_task_count; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition.scored_task_count IS 'Number of scored tasks. Outside a lesson it is required, 10 by default; in a lesson it is NULL: all tasks of the exercise after the practice ones are scored.';


--
-- Name: competition_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.competition ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.competition_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: competition_participation; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.competition_participation (
    id bigint NOT NULL,
    competition_id bigint NOT NULL,
    learning_link_id bigint NOT NULL,
    nickname text,
    team_number integer,
    joined_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_competition_participation__team_number_positive CHECK ((team_number > 0))
);


--
-- Name: TABLE competition_participation; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.competition_participation IS 'Participation of a learner in a competition. A learner joins only by own action.';


--
-- Name: COLUMN competition_participation.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition_participation.id IS 'Surrogate key.';


--
-- Name: COLUMN competition_participation.competition_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition_participation.competition_id IS 'Competition.';


--
-- Name: COLUMN competition_participation.learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition_participation.learning_link_id IS 'Learning link of the participant.';


--
-- Name: COLUMN competition_participation.nickname; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition_participation.nickname IS 'Nickname shown to other participants, unique within the competition. NULL in a lesson.';


--
-- Name: COLUMN competition_participation.team_number; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition_participation.team_number IS 'Team number. NULL when everyone competes individually.';


--
-- Name: COLUMN competition_participation.joined_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.competition_participation.joined_at IS 'Moment the learner joined.';


--
-- Name: competition_participation_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.competition_participation ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.competition_participation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: consent; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.consent (
    id bigint NOT NULL,
    app_user_id bigint NOT NULL,
    consent_kind text NOT NULL,
    given_at timestamp with time zone NOT NULL,
    policy_version_id bigint NOT NULL,
    withdrawn_at timestamp with time zone,
    CONSTRAINT ck_consent__consent_kind CHECK ((consent_kind = ANY (ARRAY['main'::text, 'statistics'::text]))),
    CONSTRAINT ck_consent__withdrawn_after_given CHECK ((withdrawn_at >= given_at))
);


--
-- Name: TABLE consent; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.consent IS 'Consent of a user, kept together with the policy version it was given under.';


--
-- Name: COLUMN consent.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.consent.id IS 'Surrogate key.';


--
-- Name: COLUMN consent.app_user_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.consent.app_user_id IS 'User who gave the consent.';


--
-- Name: COLUMN consent.consent_kind; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.consent.consent_kind IS 'Kind of consent: main or statistics.';


--
-- Name: COLUMN consent.given_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.consent.given_at IS 'Moment the consent was given.';


--
-- Name: COLUMN consent.policy_version_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.consent.policy_version_id IS 'Policy version the consent was given under.';


--
-- Name: COLUMN consent.withdrawn_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.consent.withdrawn_at IS 'Moment the consent was withdrawn. NULL while the consent is active.';


--
-- Name: consent_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.consent ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.consent_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: country; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.country (
    id bigint NOT NULL,
    name text NOT NULL,
    code text NOT NULL,
    consent_age integer NOT NULL,
    CONSTRAINT ck_country__code_format CHECK ((code ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT ck_country__consent_age_positive CHECK ((consent_age > 0))
);


--
-- Name: TABLE country; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.country IS 'Country of residence of a user. Defines the age of consent.';


--
-- Name: COLUMN country.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.country.id IS 'Surrogate key.';


--
-- Name: COLUMN country.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.country.name IS 'Country name.';


--
-- Name: COLUMN country.code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.country.code IS 'Two-letter country code, ISO 3166-1 alpha-2.';


--
-- Name: COLUMN country.consent_age; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.country.consent_age IS 'Age from which a user can give consent to data processing in this country.';


--
-- Name: country_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.country ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.country_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: course; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.course (
    id bigint NOT NULL,
    name text NOT NULL,
    owner_user_id bigint NOT NULL,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: TABLE course; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.course IS 'Own course of a self-directed learner.';


--
-- Name: COLUMN course.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.course.id IS 'Surrogate key.';


--
-- Name: COLUMN course.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.course.name IS 'Course name.';


--
-- Name: COLUMN course.owner_user_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.course.owner_user_id IS 'User who owns the course.';


--
-- Name: COLUMN course.created_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.course.created_at IS 'Moment of creation.';


--
-- Name: course_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.course ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.course_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: erasure_request; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.erasure_request (
    id bigint NOT NULL,
    app_user_id bigint,
    learning_link_id bigint,
    requested_at timestamp with time zone NOT NULL,
    confirm_by timestamp with time zone NOT NULL,
    confirmed_at timestamp with time zone,
    execute_by timestamp with time zone,
    status text NOT NULL,
    scope text NOT NULL,
    confirmation_code_hash text,
    material_retention_days integer,
    CONSTRAINT ck_erasure_request__material_retention_days_range CHECK (((material_retention_days >= 0) AND (material_retention_days <= 365))),
    CONSTRAINT ck_erasure_request__scope CHECK ((scope = ANY (ARRAY['single_link'::text, 'everything'::text]))),
    CONSTRAINT ck_erasure_request__status CHECK ((status = ANY (ARRAY['awaiting_confirmation'::text, 'confirmed'::text, 'executed'::text, 'cancelled'::text])))
);


--
-- Name: TABLE erasure_request; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.erasure_request IS 'Request of a user to erase personal data. The record outlives the erasure, without references to the person.';


--
-- Name: COLUMN erasure_request.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.erasure_request.id IS 'Surrogate key.';


--
-- Name: COLUMN erasure_request.app_user_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.erasure_request.app_user_id IS 'User who made the request. Becomes NULL after the account is deleted.';


--
-- Name: COLUMN erasure_request.learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.erasure_request.learning_link_id IS 'Learning link to erase. Becomes NULL after the erasure.';


--
-- Name: COLUMN erasure_request.requested_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.erasure_request.requested_at IS 'Moment of the request.';


--
-- Name: COLUMN erasure_request.confirm_by; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.erasure_request.confirm_by IS 'Moment by which the request must be confirmed, otherwise it is cancelled.';


--
-- Name: COLUMN erasure_request.confirmed_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.erasure_request.confirmed_at IS 'Moment of confirmation. NULL until confirmed.';


--
-- Name: COLUMN erasure_request.execute_by; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.erasure_request.execute_by IS 'Moment before which the erasure is not carried out. NULL when no term is set.';


--
-- Name: COLUMN erasure_request.status; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.erasure_request.status IS 'State: awaiting_confirmation, confirmed, executed or cancelled.';


--
-- Name: COLUMN erasure_request.scope; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.erasure_request.scope IS 'What is erased: single_link or everything.';


--
-- Name: COLUMN erasure_request.confirmation_code_hash; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.erasure_request.confirmation_code_hash IS 'Hash of the confirmation code sent by e-mail. Cleared after confirmation or cancellation.';


--
-- Name: COLUMN erasure_request.material_retention_days; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.erasure_request.material_retention_days IS 'For how many days the materials stay available to the learners after the account is erased, from 0 to 365. Chosen by the user; NULL means the default of 7 days.';


--
-- Name: erasure_request_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.erasure_request ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.erasure_request_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: error_type; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.error_type (
    id bigint NOT NULL,
    code text NOT NULL,
    name text NOT NULL
);


--
-- Name: TABLE error_type; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.error_type IS 'Kind of mistake in a learner answer: spelling, form, word choice, comprehension.';


--
-- Name: COLUMN error_type.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.error_type.id IS 'Surrogate key.';


--
-- Name: COLUMN error_type.code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.error_type.code IS 'Stable identifier used by the application. Never changed or translated.';


--
-- Name: COLUMN error_type.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.error_type.name IS 'Type name shown to users.';


--
-- Name: error_type_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.error_type ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.error_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: exercise; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.exercise (
    id bigint NOT NULL,
    parsing_run_id bigint NOT NULL,
    exercise_type_id bigint,
    topic_id bigint,
    status text NOT NULL,
    number_in_document text,
    instruction_text text NOT NULL,
    shared_body jsonb,
    source_page integer NOT NULL,
    excluded_at timestamp with time zone,
    scale_id bigint,
    source_exercise_id bigint,
    archived_at timestamp with time zone,
    is_typo_tolerated boolean DEFAULT false NOT NULL,
    CONSTRAINT ck_exercise__approved_has_scale CHECK (((status <> 'approved'::text) OR (scale_id IS NOT NULL))),
    CONSTRAINT ck_exercise__source_page_positive CHECK ((source_page > 0)),
    CONSTRAINT ck_exercise__status CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text])))
);


--
-- Name: TABLE exercise; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.exercise IS 'Exercise extracted from a material. Consists of tasks.';


--
-- Name: COLUMN exercise.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise.id IS 'Surrogate key.';


--
-- Name: COLUMN exercise.parsing_run_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise.parsing_run_id IS 'Parsing run that produced the exercise. Through it the exercise knows its material.';


--
-- Name: COLUMN exercise.exercise_type_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise.exercise_type_id IS 'Exercise type. NULL when the type was not recognised.';


--
-- Name: COLUMN exercise.topic_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise.topic_id IS 'Topic. NULL until assigned.';


--
-- Name: COLUMN exercise.status; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise.status IS 'Status: draft or approved.';


--
-- Name: COLUMN exercise.number_in_document; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise.number_in_document IS 'Number of the exercise in the document, for example 3a. Other exercises refer to it. NULL when the document gives no number.';


--
-- Name: COLUMN exercise.instruction_text; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise.instruction_text IS 'Instruction common to all tasks of the exercise.';


--
-- Name: COLUMN exercise.shared_body; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise.shared_body IS 'Part of the body shared by the tasks, such as a word bank. NULL when there is none. Structure is described in the type catalogue.';


--
-- Name: COLUMN exercise.source_page; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise.source_page IS 'Page of the document where the exercise is.';


--
-- Name: COLUMN exercise.excluded_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise.excluded_at IS 'Moment the exercise was excluded. NULL while not excluded. Cleared on return; the status stays as it was.';


--
-- Name: COLUMN exercise.scale_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise.scale_id IS 'Scale the exercise trains. Must be filled before approval.';


--
-- Name: COLUMN exercise.source_exercise_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise.source_exercise_id IS 'Exercise this one was converted from. NULL for an exercise that was not converted.';


--
-- Name: COLUMN exercise.archived_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise.archived_at IS 'Moment the exercise was moved to the archive. NULL while it is in the library.';


--
-- Name: COLUMN exercise.is_typo_tolerated; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise.is_typo_tolerated IS 'Whether a typed answer with a typo is accepted. Set by the author of the material.';


--
-- Name: exercise_dependency; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.exercise_dependency (
    id bigint NOT NULL,
    dependent_exercise_id bigint NOT NULL,
    prerequisite_exercise_id bigint NOT NULL,
    CONSTRAINT ck_exercise_dependency__different_exercises CHECK ((dependent_exercise_id <> prerequisite_exercise_id))
);


--
-- Name: TABLE exercise_dependency; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.exercise_dependency IS 'Dependency between exercises: one exercise relies on another.';


--
-- Name: COLUMN exercise_dependency.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_dependency.id IS 'Surrogate key.';


--
-- Name: COLUMN exercise_dependency.dependent_exercise_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_dependency.dependent_exercise_id IS 'Exercise that depends on another one.';


--
-- Name: COLUMN exercise_dependency.prerequisite_exercise_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_dependency.prerequisite_exercise_id IS 'Exercise it depends on.';


--
-- Name: exercise_dependency_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.exercise_dependency ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.exercise_dependency_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: exercise_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.exercise ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.exercise_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: exercise_target_word; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.exercise_target_word (
    exercise_id bigint NOT NULL,
    word_id bigint NOT NULL
);


--
-- Name: TABLE exercise_target_word; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.exercise_target_word IS 'Target word of the shared word bank of an exercise, stored once for the whole exercise.';


--
-- Name: COLUMN exercise_target_word.exercise_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_target_word.exercise_id IS 'Exercise.';


--
-- Name: COLUMN exercise_target_word.word_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_target_word.word_id IS 'Target word.';


--
-- Name: exercise_type; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.exercise_type (
    id bigint NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    recognition_features jsonb NOT NULL,
    display_mode text NOT NULL,
    checking_mode text NOT NULL,
    reference_response_time_ms integer,
    body_schema jsonb NOT NULL,
    CONSTRAINT ck_exercise_type__checking_mode CHECK ((checking_mode = ANY (ARRAY['automatic'::text, 'reviewer'::text]))),
    CONSTRAINT ck_exercise_type__display_mode CHECK ((display_mode = ANY (ARRAY['choice'::text, 'inline_choice'::text, 'pairs'::text, 'grouping'::text, 'ordering'::text, 'gap_bank'::text, 'image_gap_bank'::text, 'hotspot'::text, 'gap_bank_typed'::text, 'image_gap_bank_typed'::text, 'grouping_typed'::text, 'choice_typed'::text, 'inline_choice_typed'::text, 'pairs_typed'::text, 'text_entry'::text, 'image_text_entry'::text, 'replace_marked'::text, 'find_and_correct'::text, 'table_entry'::text, 'crossword'::text, 'word_search'::text, 'composite'::text, 'extended_text'::text, 'drawing'::text, 'audio_recording'::text]))),
    CONSTRAINT ck_exercise_type__reference_time_positive CHECK ((reference_response_time_ms > 0))
);


--
-- Name: TABLE exercise_type; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.exercise_type IS 'Catalogue of exercise types. New types are added as data, without schema changes.';


--
-- Name: COLUMN exercise_type.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_type.id IS 'Surrogate key.';


--
-- Name: COLUMN exercise_type.code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_type.code IS 'Stable identifier used by the application. Never changed or translated.';


--
-- Name: COLUMN exercise_type.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_type.name IS 'Type name shown to users.';


--
-- Name: COLUMN exercise_type.recognition_features; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_type.recognition_features IS 'Features by which the parser recognises the type in a document. Structure is described in the type catalogue.';


--
-- Name: COLUMN exercise_type.display_mode; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_type.display_mode IS 'How an exercise of this type is shown to the learner.';


--
-- Name: COLUMN exercise_type.checking_mode; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_type.checking_mode IS 'How an answer is checked: automatic or reviewer.';


--
-- Name: COLUMN exercise_type.reference_response_time_ms; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_type.reference_response_time_ms IS 'Reference response time in milliseconds. NULL when no reference is set for the type.';


--
-- Name: COLUMN exercise_type.body_schema; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_type.body_schema IS 'Description of the task body structure for this type. Task bodies are validated against it.';


--
-- Name: exercise_type_compatibility; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.exercise_type_compatibility (
    id bigint NOT NULL,
    source_type_id bigint NOT NULL,
    target_type_id bigint NOT NULL,
    is_harder boolean NOT NULL,
    CONSTRAINT ck_exercise_type_compatibility__different_types CHECK ((source_type_id <> target_type_id))
);


--
-- Name: TABLE exercise_type_compatibility; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.exercise_type_compatibility IS 'Which exercise type can be converted into which other type.';


--
-- Name: COLUMN exercise_type_compatibility.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_type_compatibility.id IS 'Surrogate key.';


--
-- Name: COLUMN exercise_type_compatibility.source_type_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_type_compatibility.source_type_id IS 'Type the exercise has.';


--
-- Name: COLUMN exercise_type_compatibility.target_type_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_type_compatibility.target_type_id IS 'Type the exercise can be converted into.';


--
-- Name: COLUMN exercise_type_compatibility.is_harder; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.exercise_type_compatibility.is_harder IS 'True when the target type is harder than the source type.';


--
-- Name: exercise_type_compatibility_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.exercise_type_compatibility ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.exercise_type_compatibility_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: exercise_type_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.exercise_type ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.exercise_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: export_request; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.export_request (
    id bigint NOT NULL,
    app_user_id bigint NOT NULL,
    learning_link_id bigint,
    requested_at timestamp with time zone NOT NULL,
    prepare_by timestamp with time zone NOT NULL,
    prepared_at timestamp with time zone,
    file_location text,
    available_until timestamp with time zone
);


--
-- Name: TABLE export_request; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.export_request IS 'Request of a user to export own data. The state of the request is derived from its dates.';


--
-- Name: COLUMN export_request.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.export_request.id IS 'Surrogate key.';


--
-- Name: COLUMN export_request.app_user_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.export_request.app_user_id IS 'User who requested the export.';


--
-- Name: COLUMN export_request.learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.export_request.learning_link_id IS 'Learning link whose data is exported. NULL when all data of the user is exported.';


--
-- Name: COLUMN export_request.requested_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.export_request.requested_at IS 'Moment the export was requested.';


--
-- Name: COLUMN export_request.prepare_by; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.export_request.prepare_by IS 'Deadline for preparing the export, no later than one month after the request.';


--
-- Name: COLUMN export_request.prepared_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.export_request.prepared_at IS 'Moment the export was prepared. NULL while it is being prepared.';


--
-- Name: COLUMN export_request.file_location; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.export_request.file_location IS 'Address of the export file. NULL until the export is ready.';


--
-- Name: COLUMN export_request.available_until; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.export_request.available_until IS 'Moment until which the file can be downloaded. NULL until the export is ready.';


--
-- Name: export_request_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.export_request ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.export_request_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: feature_toggle; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.feature_toggle (
    id bigint NOT NULL,
    feature text NOT NULL,
    study_group_id bigint,
    learning_link_id bigint,
    is_enabled boolean NOT NULL,
    changed_at timestamp with time zone NOT NULL,
    CONSTRAINT ck_feature_toggle__feature CHECK ((feature = ANY (ARRAY['adaptation'::text, 'harder_variants'::text, 'oral_error_entry'::text]))),
    CONSTRAINT ck_feature_toggle__one_target CHECK ((num_nonnulls(study_group_id, learning_link_id) = 1))
);


--
-- Name: TABLE feature_toggle; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.feature_toggle IS 'Feature switched on or off by a teacher for a group or for one learner. A row exists only where the teacher changed the default; the setting of a learner overrides the setting of the group.';


--
-- Name: COLUMN feature_toggle.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.feature_toggle.id IS 'Surrogate key.';


--
-- Name: COLUMN feature_toggle.feature; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.feature_toggle.feature IS 'Feature: adaptation, harder_variants or oral_error_entry.';


--
-- Name: COLUMN feature_toggle.study_group_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.feature_toggle.study_group_id IS 'Group the setting applies to. Exactly one of study_group_id and learning_link_id is filled.';


--
-- Name: COLUMN feature_toggle.learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.feature_toggle.learning_link_id IS 'Learning link the setting applies to: a setting for one learner.';


--
-- Name: COLUMN feature_toggle.is_enabled; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.feature_toggle.is_enabled IS 'True when the feature is switched on.';


--
-- Name: COLUMN feature_toggle.changed_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.feature_toggle.changed_at IS 'Moment the setting was last changed.';


--
-- Name: feature_toggle_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.feature_toggle ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.feature_toggle_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: flag; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.flag (
    id bigint NOT NULL,
    task_id bigint,
    exercise_id bigint,
    place_in_task text,
    flag_reason_id bigint NOT NULL,
    status text NOT NULL,
    original_value text,
    placed_by_user_id bigint,
    placed_at timestamp with time zone NOT NULL,
    closed_at timestamp with time zone,
    CONSTRAINT ck_flag__one_target CHECK ((num_nonnulls(task_id, exercise_id) = 1)),
    CONSTRAINT ck_flag__status CHECK ((status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'corrected'::text])))
);


--
-- Name: TABLE flag; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.flag IS 'Flag on a doubtful place of parsed material that the author must confirm or correct.';


--
-- Name: COLUMN flag.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.flag.id IS 'Surrogate key.';


--
-- Name: COLUMN flag.task_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.flag.task_id IS 'Flagged task. Exactly one of task_id and exercise_id is filled.';


--
-- Name: COLUMN flag.exercise_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.flag.exercise_id IS 'Flagged exercise. Exactly one of task_id and exercise_id is filled.';


--
-- Name: COLUMN flag.place_in_task; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.flag.place_in_task IS 'Flagged part of the task body: which gap or answer. NULL when the whole task is flagged.';


--
-- Name: COLUMN flag.flag_reason_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.flag.flag_reason_id IS 'Reason of the flag.';


--
-- Name: COLUMN flag.status; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.flag.status IS 'State: pending, confirmed or corrected.';


--
-- Name: COLUMN flag.original_value; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.flag.original_value IS 'Value that stood in the document before the author corrected it. NULL until a correction is made.';


--
-- Name: COLUMN flag.placed_by_user_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.flag.placed_by_user_id IS 'User who placed the flag. NULL when the system placed it during parsing.';


--
-- Name: COLUMN flag.placed_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.flag.placed_at IS 'Moment the flag was placed.';


--
-- Name: COLUMN flag.closed_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.flag.closed_at IS 'Moment the flag was closed. NULL while it is pending.';


--
-- Name: flag_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.flag ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.flag_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: flag_reason; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.flag_reason (
    id bigint NOT NULL,
    code text NOT NULL,
    name text NOT NULL
);


--
-- Name: TABLE flag_reason; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.flag_reason IS 'Reason why a place in parsed material is flagged for the author to confirm.';


--
-- Name: COLUMN flag_reason.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.flag_reason.id IS 'Surrogate key.';


--
-- Name: COLUMN flag_reason.code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.flag_reason.code IS 'Stable identifier used by the application. Never changed or translated.';


--
-- Name: COLUMN flag_reason.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.flag_reason.name IS 'Reason shown to the author next to the flagged place.';


--
-- Name: flag_reason_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.flag_reason ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.flag_reason_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: folder; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.folder (
    id bigint NOT NULL,
    owner_user_id bigint NOT NULL,
    name text NOT NULL,
    parent_folder_id bigint,
    folder_kind text NOT NULL,
    split_method text,
    CONSTRAINT ck_folder__folder_kind CHECK ((folder_kind = ANY (ARRAY['ordinary'::text, 'book'::text]))),
    CONSTRAINT ck_folder__split_method CHECK ((split_method = ANY (ARRAY['by_contents'::text, 'by_headings'::text, 'by_equal_ranges'::text]))),
    CONSTRAINT ck_folder__split_only_for_book CHECK (((split_method IS NULL) OR (folder_kind = 'book'::text)))
);


--
-- Name: TABLE folder; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.folder IS 'Folder of the material library. A folder of kind book holds the parts of one large document.';


--
-- Name: COLUMN folder.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.folder.id IS 'Surrogate key.';


--
-- Name: COLUMN folder.owner_user_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.folder.owner_user_id IS 'User who owns the folder.';


--
-- Name: COLUMN folder.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.folder.name IS 'Folder name.';


--
-- Name: COLUMN folder.parent_folder_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.folder.parent_folder_id IS 'Folder that contains this one. NULL for a top-level folder.';


--
-- Name: COLUMN folder.folder_kind; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.folder.folder_kind IS 'Kind: ordinary or book.';


--
-- Name: COLUMN folder.split_method; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.folder.split_method IS 'How the document was split into parts: by_contents, by_headings or by_equal_ranges. Filled only for a book, NULL for an ordinary folder.';


--
-- Name: folder_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.folder ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.folder_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: group_membership; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.group_membership (
    id bigint NOT NULL,
    learning_link_id bigint NOT NULL,
    study_group_id bigint NOT NULL,
    joined_at timestamp with time zone NOT NULL,
    left_at timestamp with time zone,
    CONSTRAINT ck_group_membership__left_after_joined CHECK ((left_at >= joined_at))
);


--
-- Name: TABLE group_membership; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.group_membership IS 'Membership of a learning link in a group, with its history.';


--
-- Name: COLUMN group_membership.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.group_membership.id IS 'Surrogate key.';


--
-- Name: COLUMN group_membership.learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.group_membership.learning_link_id IS 'Learning link of the member.';


--
-- Name: COLUMN group_membership.study_group_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.group_membership.study_group_id IS 'Group.';


--
-- Name: COLUMN group_membership.joined_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.group_membership.joined_at IS 'Moment of joining.';


--
-- Name: COLUMN group_membership.left_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.group_membership.left_at IS 'Moment of leaving. NULL while a member. Results stay in the group archive afterwards.';


--
-- Name: group_membership_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.group_membership ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.group_membership_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: homework; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.homework (
    id bigint NOT NULL,
    assigned_by_user_id bigint NOT NULL,
    study_group_id bigint,
    due_at timestamp with time zone NOT NULL,
    assigned_at timestamp with time zone NOT NULL,
    adaptation_proposal_id bigint,
    CONSTRAINT ck_homework__due_after_assigned CHECK ((due_at >= assigned_at))
);


--
-- Name: TABLE homework; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.homework IS 'Homework assigned by a teacher to a group or to one learner.';


--
-- Name: COLUMN homework.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework.id IS 'Surrogate key.';


--
-- Name: COLUMN homework.assigned_by_user_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework.assigned_by_user_id IS 'Teacher who assigned the homework.';


--
-- Name: COLUMN homework.study_group_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework.study_group_id IS 'Group the homework is assigned to. NULL when assigned to one learner.';


--
-- Name: COLUMN homework.due_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework.due_at IS 'Deadline, as a moment in time.';


--
-- Name: COLUMN homework.assigned_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework.assigned_at IS 'Moment of assignment.';


--
-- Name: COLUMN homework.adaptation_proposal_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework.adaptation_proposal_id IS 'Adaptation proposal the homework was created from. NULL when assigned manually.';


--
-- Name: homework_assignment; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.homework_assignment (
    id bigint NOT NULL,
    homework_id bigint NOT NULL,
    learning_link_id bigint NOT NULL,
    personal_note text,
    completed_at timestamp with time zone
);


--
-- Name: TABLE homework_assignment; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.homework_assignment IS 'Homework as received by one learner.';


--
-- Name: COLUMN homework_assignment.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework_assignment.id IS 'Surrogate key.';


--
-- Name: COLUMN homework_assignment.homework_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework_assignment.homework_id IS 'Homework.';


--
-- Name: COLUMN homework_assignment.learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework_assignment.learning_link_id IS 'Learning link of the learner who received it.';


--
-- Name: COLUMN homework_assignment.personal_note; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework_assignment.personal_note IS 'Note visible to this learner only. NULL when there is none.';


--
-- Name: COLUMN homework_assignment.completed_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework_assignment.completed_at IS 'Moment of completion. NULL until completed. Completion is counted by the main items; additional items do not affect it.';


--
-- Name: homework_assignment_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.homework_assignment ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.homework_assignment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: homework_exercise; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.homework_exercise (
    homework_id bigint NOT NULL,
    exercise_id bigint NOT NULL,
    sort_order integer NOT NULL,
    item_kind text DEFAULT 'main'::text NOT NULL,
    CONSTRAINT ck_homework_exercise__item_kind CHECK ((item_kind = ANY (ARRAY['main'::text, 'additional'::text]))),
    CONSTRAINT ck_homework_exercise__sort_order_positive CHECK ((sort_order > 0))
);


--
-- Name: TABLE homework_exercise; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.homework_exercise IS 'Whole exercise included in a homework.';


--
-- Name: COLUMN homework_exercise.homework_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework_exercise.homework_id IS 'Homework.';


--
-- Name: COLUMN homework_exercise.exercise_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework_exercise.exercise_id IS 'Exercise included in it.';


--
-- Name: COLUMN homework_exercise.sort_order; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework_exercise.sort_order IS 'Position of the exercise in the homework.';


--
-- Name: COLUMN homework_exercise.item_kind; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework_exercise.item_kind IS 'Kind: main or additional. Additional items are harder and optional.';


--
-- Name: homework_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.homework ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.homework_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: homework_task; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.homework_task (
    homework_id bigint NOT NULL,
    task_id bigint NOT NULL,
    sort_order integer NOT NULL,
    item_kind text DEFAULT 'main'::text NOT NULL,
    CONSTRAINT ck_homework_task__item_kind CHECK ((item_kind = ANY (ARRAY['main'::text, 'additional'::text]))),
    CONSTRAINT ck_homework_task__sort_order_positive CHECK ((sort_order > 0))
);


--
-- Name: TABLE homework_task; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.homework_task IS 'Separate task included in a homework.';


--
-- Name: COLUMN homework_task.homework_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework_task.homework_id IS 'Homework.';


--
-- Name: COLUMN homework_task.task_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework_task.task_id IS 'Task included in it.';


--
-- Name: COLUMN homework_task.sort_order; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework_task.sort_order IS 'Position of the task in the homework.';


--
-- Name: COLUMN homework_task.item_kind; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.homework_task.item_kind IS 'Kind: main or additional. Additional items are harder and optional.';


--
-- Name: image; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.image (
    id bigint NOT NULL,
    task_id bigint,
    exercise_id bigint,
    file_location text NOT NULL,
    origin text NOT NULL,
    source_page integer NOT NULL,
    image_kind text NOT NULL,
    source_image_id bigint,
    confirmed_at timestamp with time zone,
    CONSTRAINT ck_image__image_kind CHECK ((image_kind = ANY (ARRAY['ordinary'::text, 'grid'::text, 'diagram'::text]))),
    CONSTRAINT ck_image__one_target CHECK ((num_nonnulls(task_id, exercise_id) = 1)),
    CONSTRAINT ck_image__origin CHECK ((origin = ANY (ARRAY['source'::text, 'redrawn'::text]))),
    CONSTRAINT ck_image__origin_matches_source CHECK ((((origin = 'redrawn'::text) AND (source_image_id IS NOT NULL)) OR ((origin = 'source'::text) AND (source_image_id IS NULL)))),
    CONSTRAINT ck_image__source_page_positive CHECK ((source_page > 0))
);


--
-- Name: TABLE image; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.image IS 'Image that belongs to a task or to a whole exercise. The file itself is stored outside the database.';


--
-- Name: COLUMN image.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.image.id IS 'Surrogate key.';


--
-- Name: COLUMN image.task_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.image.task_id IS 'Task the image belongs to. Exactly one of task_id and exercise_id is filled.';


--
-- Name: COLUMN image.exercise_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.image.exercise_id IS 'Exercise the image belongs to. Exactly one of task_id and exercise_id is filled.';


--
-- Name: COLUMN image.file_location; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.image.file_location IS 'Address of the file.';


--
-- Name: COLUMN image.origin; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.image.origin IS 'Origin: source (taken from the document) or redrawn.';


--
-- Name: COLUMN image.source_page; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.image.source_page IS 'Page of the document where the image is.';


--
-- Name: COLUMN image.image_kind; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.image.image_kind IS 'Kind: ordinary, grid or diagram. Redrawing is not offered for a grid or a diagram.';


--
-- Name: COLUMN image.source_image_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.image.source_image_id IS 'Image this one was redrawn from. Filled only for a redrawn image.';


--
-- Name: COLUMN image.confirmed_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.image.confirmed_at IS 'Moment the author confirmed the redrawn image. NULL while it waits for the decision; always NULL for a source image.';


--
-- Name: image_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.image ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.image_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: invitation; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.invitation (
    id bigint NOT NULL,
    study_group_id bigint NOT NULL,
    code text NOT NULL,
    valid_until timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone
);


--
-- Name: TABLE invitation; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.invitation IS 'Invitation to join a group by a link.';


--
-- Name: COLUMN invitation.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.invitation.id IS 'Surrogate key.';


--
-- Name: COLUMN invitation.study_group_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.invitation.study_group_id IS 'Group the invitation leads to.';


--
-- Name: COLUMN invitation.code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.invitation.code IS 'Random value from which the link address is built.';


--
-- Name: COLUMN invitation.valid_until; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.invitation.valid_until IS 'Moment until which the invitation is valid.';


--
-- Name: COLUMN invitation.revoked_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.invitation.revoked_at IS 'Moment the invitation was revoked. NULL while not revoked.';


--
-- Name: invitation_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.invitation ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.invitation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: language; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.language (
    id bigint NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    CONSTRAINT ck_language__code_format CHECK ((code ~ '^[a-z]{2}$'::text))
);


--
-- Name: TABLE language; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.language IS 'Language: studied language or interface language.';


--
-- Name: COLUMN language.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.language.id IS 'Surrogate key.';


--
-- Name: COLUMN language.code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.language.code IS 'Two-letter language code, ISO 639-1, for example en. Never changed or translated.';


--
-- Name: COLUMN language.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.language.name IS 'Language name shown to users.';


--
-- Name: language_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.language ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.language_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: learning_link; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.learning_link (
    id bigint NOT NULL,
    link_kind text NOT NULL,
    learner_user_id bigint NOT NULL,
    teacher_user_id bigint,
    course_id bigint,
    goal text,
    target_cefr_level_id bigint,
    started_at timestamp with time zone NOT NULL,
    ended_at timestamp with time zone,
    study_language_id bigint NOT NULL,
    level_decision_mode text NOT NULL,
    adaptation_decision_mode text NOT NULL,
    queue_decision_mode text NOT NULL,
    total_course_hours integer,
    desired_end_date date,
    new_material_share numeric(3,2) DEFAULT 0.10 NOT NULL,
    failures_before_deferral integer DEFAULT 8 NOT NULL,
    access_until date,
    CONSTRAINT ck_learning_link__access_after_end CHECK (((access_until IS NULL) OR ((link_kind = 'with_teacher'::text) AND (ended_at IS NOT NULL) AND (access_until >= ((ended_at AT TIME ZONE 'UTC'::text))::date) AND (access_until <= (((ended_at AT TIME ZONE 'UTC'::text))::date + 365))))),
    CONSTRAINT ck_learning_link__adaptation_decision_mode CHECK ((adaptation_decision_mode = ANY (ARRAY['self'::text, 'system'::text]))),
    CONSTRAINT ck_learning_link__ended_after_started CHECK ((ended_at >= started_at)),
    CONSTRAINT ck_learning_link__failures_before_deferral_positive CHECK ((failures_before_deferral > 0)),
    CONSTRAINT ck_learning_link__kind_consistency CHECK ((((link_kind = 'self_directed'::text) AND (course_id IS NOT NULL) AND (teacher_user_id IS NULL)) OR ((link_kind = 'with_teacher'::text) AND (course_id IS NULL)))),
    CONSTRAINT ck_learning_link__level_decision_mode CHECK ((level_decision_mode = ANY (ARRAY['self'::text, 'system'::text]))),
    CONSTRAINT ck_learning_link__link_kind CHECK ((link_kind = ANY (ARRAY['with_teacher'::text, 'self_directed'::text]))),
    CONSTRAINT ck_learning_link__new_material_share_range CHECK (((new_material_share >= (0)::numeric) AND (new_material_share <= (1)::numeric))),
    CONSTRAINT ck_learning_link__queue_decision_mode CHECK ((queue_decision_mode = ANY (ARRAY['self'::text, 'system'::text]))),
    CONSTRAINT ck_learning_link__teacher_present CHECK (((link_kind <> 'with_teacher'::text) OR (teacher_user_id IS NOT NULL) OR (ended_at IS NOT NULL))),
    CONSTRAINT ck_learning_link__total_course_hours_positive CHECK ((total_course_hours > 0))
);


--
-- Name: TABLE learning_link; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.learning_link IS 'Learning link: a learner with a teacher, or a learner with an own course. History, answers and level belong to the link, not to the person.';


--
-- Name: COLUMN learning_link.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.id IS 'Surrogate key.';


--
-- Name: COLUMN learning_link.link_kind; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.link_kind IS 'Kind of link: with_teacher or self_directed.';


--
-- Name: COLUMN learning_link.learner_user_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.learner_user_id IS 'User who learns.';


--
-- Name: COLUMN learning_link.teacher_user_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.teacher_user_id IS 'Teacher. NULL for a self-directed link and after the teacher account is deleted.';


--
-- Name: COLUMN learning_link.course_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.course_id IS 'Own course. Filled for a self-directed link only.';


--
-- Name: COLUMN learning_link.goal; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.goal IS 'Learning goal in the words of the user. NULL until set.';


--
-- Name: COLUMN learning_link.target_cefr_level_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.target_cefr_level_id IS 'Target CEFR level. NULL until the goal is set.';


--
-- Name: COLUMN learning_link.started_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.started_at IS 'Moment the link started.';


--
-- Name: COLUMN learning_link.ended_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.ended_at IS 'Moment the link ended. NULL while the link is active. After it the teacher sees nothing further.';


--
-- Name: COLUMN learning_link.study_language_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.study_language_id IS 'Language studied within the link.';


--
-- Name: COLUMN learning_link.level_decision_mode; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.level_decision_mode IS 'Who records a level change: self (the user decides) or system (the system is trusted).';


--
-- Name: COLUMN learning_link.adaptation_decision_mode; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.adaptation_decision_mode IS 'Who approves an adaptation proposal: self (the user decides) or system (the system is trusted).';


--
-- Name: COLUMN learning_link.queue_decision_mode; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.queue_decision_mode IS 'Who decides on the revision queue: self (the user decides) or system (the system is trusted).';


--
-- Name: COLUMN learning_link.total_course_hours; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.total_course_hours IS 'Total time budget of the course in hours. NULL until it is set.';


--
-- Name: COLUMN learning_link.desired_end_date; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.desired_end_date IS 'Date by which the learner wants to finish. NULL until it is set.';


--
-- Name: COLUMN learning_link.new_material_share; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.new_material_share IS 'Share of new material in the daily queue, from 0 to 1. The learner can change it.';


--
-- Name: COLUMN learning_link.failures_before_deferral; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.failures_before_deferral IS 'Number of failed attempts after which a task is deferred instead of being repeated.';


--
-- Name: COLUMN learning_link.access_until; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link.access_until IS 'Last day the learner may go on revising the exercises of a closed link with a teacher, at most 365 days after the end. NULL when no such access is left.';


--
-- Name: learning_link_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.learning_link ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.learning_link_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: learning_link_pseudonym; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.learning_link_pseudonym (
    id bigint NOT NULL,
    learning_link_id bigint NOT NULL,
    random_code uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: TABLE learning_link_pseudonym; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.learning_link_pseudonym IS 'Correspondence between a learning link and the random code used in statistics. The only key from statistics back to a person; deleted with the link or when the statistics consent is withdrawn.';


--
-- Name: COLUMN learning_link_pseudonym.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link_pseudonym.id IS 'Surrogate key.';


--
-- Name: COLUMN learning_link_pseudonym.learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link_pseudonym.learning_link_id IS 'Learning link. One code per link.';


--
-- Name: COLUMN learning_link_pseudonym.random_code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link_pseudonym.random_code IS 'Random code generated by the database.';


--
-- Name: COLUMN learning_link_pseudonym.created_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.learning_link_pseudonym.created_at IS 'Moment the code was created.';


--
-- Name: learning_link_pseudonym_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.learning_link_pseudonym ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.learning_link_pseudonym_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: lesson; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.lesson (
    id bigint NOT NULL,
    study_group_id bigint,
    learning_link_id bigint,
    started_at timestamp with time zone NOT NULL,
    ended_at timestamp with time zone,
    CONSTRAINT ck_lesson__ended_after_started CHECK ((ended_at >= started_at)),
    CONSTRAINT ck_lesson__one_target CHECK ((num_nonnulls(study_group_id, learning_link_id) = 1))
);


--
-- Name: TABLE lesson; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.lesson IS 'Lesson held by a teacher: with a group or with one learner.';


--
-- Name: COLUMN lesson.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.lesson.id IS 'Surrogate key.';


--
-- Name: COLUMN lesson.study_group_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.lesson.study_group_id IS 'Group, for a group lesson. Exactly one of study_group_id and learning_link_id is filled.';


--
-- Name: COLUMN lesson.learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.lesson.learning_link_id IS 'Learning link, for an individual lesson. Exactly one of study_group_id and learning_link_id is filled.';


--
-- Name: COLUMN lesson.started_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.lesson.started_at IS 'Moment the lesson started.';


--
-- Name: COLUMN lesson.ended_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.lesson.ended_at IS 'Moment the lesson ended. NULL while the lesson is in progress.';


--
-- Name: lesson_exercise; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.lesson_exercise (
    id bigint NOT NULL,
    lesson_id bigint NOT NULL,
    exercise_id bigint NOT NULL,
    shown_to_learning_link_id bigint,
    opened_at timestamp with time zone NOT NULL
);


--
-- Name: TABLE lesson_exercise; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.lesson_exercise IS 'Exercise opened by the teacher during a lesson.';


--
-- Name: COLUMN lesson_exercise.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.lesson_exercise.id IS 'Surrogate key.';


--
-- Name: COLUMN lesson_exercise.lesson_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.lesson_exercise.lesson_id IS 'Lesson.';


--
-- Name: COLUMN lesson_exercise.exercise_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.lesson_exercise.exercise_id IS 'Exercise that was opened.';


--
-- Name: COLUMN lesson_exercise.shown_to_learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.lesson_exercise.shown_to_learning_link_id IS 'Learning link of the learner the exercise was shown to. NULL when shown to everyone.';


--
-- Name: COLUMN lesson_exercise.opened_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.lesson_exercise.opened_at IS 'Moment the exercise was opened.';


--
-- Name: lesson_exercise_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.lesson_exercise ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.lesson_exercise_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: lesson_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.lesson ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.lesson_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: level_change; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.level_change (
    id bigint NOT NULL,
    scale_level_id bigint NOT NULL,
    previous_cefr_level_id bigint NOT NULL,
    new_cefr_level_id bigint NOT NULL,
    changed_at timestamp with time zone NOT NULL,
    changed_by text NOT NULL,
    shown_to_learner_at timestamp with time zone,
    CONSTRAINT ck_level_change__changed_by CHECK ((changed_by = ANY (ARRAY['system'::text, 'user'::text]))),
    CONSTRAINT ck_level_change__levels_differ CHECK ((new_cefr_level_id <> previous_cefr_level_id))
);


--
-- Name: TABLE level_change; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.level_change IS 'Journal of level changes on a scale. A row is written once and is not changed afterwards, except for the moment it was shown to the learner.';


--
-- Name: COLUMN level_change.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.level_change.id IS 'Surrogate key.';


--
-- Name: COLUMN level_change.scale_level_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.level_change.scale_level_id IS 'Level on a scale that changed. Identifies both the learning link and the scale.';


--
-- Name: COLUMN level_change.previous_cefr_level_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.level_change.previous_cefr_level_id IS 'Level before the change.';


--
-- Name: COLUMN level_change.new_cefr_level_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.level_change.new_cefr_level_id IS 'Level after the change. Differs from the previous level.';


--
-- Name: COLUMN level_change.changed_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.level_change.changed_at IS 'Moment of the change.';


--
-- Name: COLUMN level_change.changed_by; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.level_change.changed_by IS 'Who made the change: system or user. Not a reference to a user.';


--
-- Name: COLUMN level_change.shown_to_learner_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.level_change.shown_to_learner_at IS 'Moment the congratulation was shown to the learner. NULL until it is shown.';


--
-- Name: level_change_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.level_change ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.level_change_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: material; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.material (
    id bigint NOT NULL,
    owner_user_id bigint,
    name text NOT NULL,
    file_location text NOT NULL,
    file_size_bytes integer NOT NULL,
    page_count integer NOT NULL,
    has_text_layer boolean NOT NULL,
    cefr_level_id bigint,
    study_language_id bigint NOT NULL,
    processing_status text NOT NULL,
    uploaded_at timestamp with time zone NOT NULL,
    course_id bigint,
    folder_id bigint,
    part_number integer,
    source_page_from integer,
    source_page_to integer,
    archived_at timestamp with time zone,
    retained_until date,
    CONSTRAINT ck_material__file_size_positive CHECK ((file_size_bytes > 0)),
    CONSTRAINT ck_material__ownerless_is_retained CHECK (((owner_user_id IS NULL) = (retained_until IS NOT NULL))),
    CONSTRAINT ck_material__page_count_positive CHECK ((page_count > 0)),
    CONSTRAINT ck_material__part_number_positive CHECK ((part_number > 0)),
    CONSTRAINT ck_material__processing_status CHECK ((processing_status = ANY (ARRAY['processing'::text, 'parsed'::text, 'text_not_extracted'::text, 'not_parsed'::text]))),
    CONSTRAINT ck_material__source_pages CHECK ((((source_page_from IS NULL) AND (source_page_to IS NULL)) OR ((source_page_from IS NOT NULL) AND (source_page_to IS NOT NULL) AND (source_page_from <= source_page_to))))
);


--
-- Name: TABLE material; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.material IS 'Uploaded PDF learning material. The file itself is stored outside the database.';


--
-- Name: COLUMN material.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.id IS 'Surrogate key.';


--
-- Name: COLUMN material.owner_user_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.owner_user_id IS 'Owner of the material. NULL when the owner erased the account and the material is kept for the learners until retained_until.';


--
-- Name: COLUMN material.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.name IS 'Material name. Used for search in the library.';


--
-- Name: COLUMN material.file_location; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.file_location IS 'Address of the file.';


--
-- Name: COLUMN material.file_size_bytes; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.file_size_bytes IS 'File size in bytes. The size limit is an application setting, not a database rule.';


--
-- Name: COLUMN material.page_count; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.page_count IS 'Number of pages. The page limit is an application setting.';


--
-- Name: COLUMN material.has_text_layer; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.has_text_layer IS 'True when the PDF has a text layer.';


--
-- Name: COLUMN material.cefr_level_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.cefr_level_id IS 'Level of the material, set by the uploader. NULL until set.';


--
-- Name: COLUMN material.study_language_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.study_language_id IS 'Language the material teaches. Dictionaries and audio depend on it.';


--
-- Name: COLUMN material.processing_status; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.processing_status IS 'Processing status: processing, parsed, text_not_extracted or not_parsed.';


--
-- Name: COLUMN material.uploaded_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.uploaded_at IS 'Moment of upload.';


--
-- Name: COLUMN material.course_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.course_id IS 'Own course the material belongs to. NULL for a material of a teacher.';


--
-- Name: COLUMN material.folder_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.folder_id IS 'Folder the material lies in. NULL when it lies outside folders.';


--
-- Name: COLUMN material.part_number; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.part_number IS 'Number of the part inside a book. NULL for an ordinary material.';


--
-- Name: COLUMN material.source_page_from; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.source_page_from IS 'First page of the part in the source document. NULL for an ordinary material.';


--
-- Name: COLUMN material.source_page_to; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.source_page_to IS 'Last page of the part in the source document. NULL for an ordinary material.';


--
-- Name: COLUMN material.archived_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.archived_at IS 'Moment the material was moved to the archive. NULL while it is in the library.';


--
-- Name: COLUMN material.retained_until; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.material.retained_until IS 'Last day the material of an erased owner is kept for the learners who worked with it. NULL for a material with an owner.';


--
-- Name: material_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.material ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.material_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: note; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.note (
    id bigint NOT NULL,
    learning_link_id bigint NOT NULL,
    lesson_id bigint,
    note_text text NOT NULL,
    written_at timestamp with time zone NOT NULL
);


--
-- Name: TABLE note; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.note IS 'Note of a teacher about a learner.';


--
-- Name: COLUMN note.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.note.id IS 'Surrogate key.';


--
-- Name: COLUMN note.learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.note.learning_link_id IS 'Learning link the note belongs to.';


--
-- Name: COLUMN note.lesson_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.note.lesson_id IS 'Lesson the note was written at. May be NULL.';


--
-- Name: COLUMN note.note_text; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.note.note_text IS 'Personal data. Free text about the learner.';


--
-- Name: COLUMN note.written_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.note.written_at IS 'Moment the note was written.';


--
-- Name: note_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.note ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.note_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: oral_error; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.oral_error (
    id bigint NOT NULL,
    learning_link_id bigint NOT NULL,
    lesson_id bigint,
    task_id bigint,
    topic_id bigint,
    scale_id bigint NOT NULL,
    phrase text,
    recorded_at timestamp with time zone NOT NULL,
    error_type_id bigint
);


--
-- Name: TABLE oral_error; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.oral_error IS 'Oral error of a learner, recorded by the teacher during a lesson.';


--
-- Name: COLUMN oral_error.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.oral_error.id IS 'Surrogate key.';


--
-- Name: COLUMN oral_error.learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.oral_error.learning_link_id IS 'Learning link of the learner.';


--
-- Name: COLUMN oral_error.lesson_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.oral_error.lesson_id IS 'Lesson during which the error was recorded. Becomes NULL when the lesson is deleted.';


--
-- Name: COLUMN oral_error.task_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.oral_error.task_id IS 'Task that was open at that moment. May be NULL.';


--
-- Name: COLUMN oral_error.topic_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.oral_error.topic_id IS 'Topic of the error. Taken from the current task; the teacher can change it.';


--
-- Name: COLUMN oral_error.scale_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.oral_error.scale_id IS 'Scale the error relates to. Speech by default.';


--
-- Name: COLUMN oral_error.phrase; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.oral_error.phrase IS 'Word or phrase with the error. Optional; can be added after the lesson.';


--
-- Name: COLUMN oral_error.recorded_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.oral_error.recorded_at IS 'Moment the error was recorded.';


--
-- Name: COLUMN oral_error.error_type_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.oral_error.error_type_id IS 'Type of the mistake. NULL until it is specified.';


--
-- Name: oral_error_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.oral_error ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.oral_error_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: parsing_run; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.parsing_run (
    id bigint NOT NULL,
    material_id bigint NOT NULL,
    started_at timestamp with time zone NOT NULL,
    finished_at timestamp with time zone,
    outcome text,
    CONSTRAINT ck_parsing_run__finished_after_started CHECK ((finished_at >= started_at)),
    CONSTRAINT ck_parsing_run__outcome CHECK ((outcome = ANY (ARRAY['completed'::text, 'timed_out'::text, 'text_not_extracted'::text])))
);


--
-- Name: TABLE parsing_run; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.parsing_run IS 'One run of parsing a material into exercises.';


--
-- Name: COLUMN parsing_run.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.parsing_run.id IS 'Surrogate key.';


--
-- Name: COLUMN parsing_run.material_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.parsing_run.material_id IS 'Material that was parsed.';


--
-- Name: COLUMN parsing_run.started_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.parsing_run.started_at IS 'Moment the run started.';


--
-- Name: COLUMN parsing_run.finished_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.parsing_run.finished_at IS 'Moment the run finished. NULL while running. Distinguishes a running parse from a stalled one.';


--
-- Name: COLUMN parsing_run.outcome; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.parsing_run.outcome IS 'Outcome: completed, timed_out or text_not_extracted. NULL while running.';


--
-- Name: parsing_run_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.parsing_run ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.parsing_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: policy_version; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.policy_version (
    id bigint NOT NULL,
    version_number text NOT NULL,
    effective_from date NOT NULL,
    policy_text text NOT NULL
);


--
-- Name: TABLE policy_version; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.policy_version IS 'Version of the data processing policy that users consent to.';


--
-- Name: COLUMN policy_version.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.policy_version.id IS 'Surrogate key.';


--
-- Name: COLUMN policy_version.version_number; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.policy_version.version_number IS 'Version number, for example 1.2.';


--
-- Name: COLUMN policy_version.effective_from; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.policy_version.effective_from IS 'Date from which the version is in force.';


--
-- Name: COLUMN policy_version.policy_text; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.policy_version.policy_text IS 'Full text of the version, so that it is clear what exactly a user consented to.';


--
-- Name: policy_version_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.policy_version ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.policy_version_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: presentation_item; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.presentation_item (
    id bigint NOT NULL,
    exercise_id bigint,
    task_id bigint,
    item_kind text NOT NULL,
    content text,
    file_location text,
    generated_at timestamp with time zone NOT NULL,
    confirmed_at timestamp with time zone,
    CONSTRAINT ck_presentation_item__content_matches_kind CHECK ((((item_kind = 'illustration'::text) AND (file_location IS NOT NULL) AND (content IS NULL)) OR ((item_kind = ANY (ARRAY['hint'::text, 'glossary'::text])) AND (content IS NOT NULL) AND (file_location IS NULL)))),
    CONSTRAINT ck_presentation_item__item_kind CHECK ((item_kind = ANY (ARRAY['illustration'::text, 'hint'::text, 'glossary'::text]))),
    CONSTRAINT ck_presentation_item__one_target CHECK ((num_nonnulls(exercise_id, task_id) = 1))
);


--
-- Name: TABLE presentation_item; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.presentation_item IS 'Presentation element added to an exercise or a task on request: illustration, hint or glossary. It never changes the content of tasks and keys.';


--
-- Name: COLUMN presentation_item.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.presentation_item.id IS 'Surrogate key.';


--
-- Name: COLUMN presentation_item.exercise_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.presentation_item.exercise_id IS 'Exercise the element belongs to. Exactly one of exercise_id and task_id is filled.';


--
-- Name: COLUMN presentation_item.task_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.presentation_item.task_id IS 'Task the element belongs to. Exactly one of exercise_id and task_id is filled.';


--
-- Name: COLUMN presentation_item.item_kind; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.presentation_item.item_kind IS 'Kind: illustration, hint or glossary.';


--
-- Name: COLUMN presentation_item.content; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.presentation_item.content IS 'Text of the hint or glossary. NULL for an illustration.';


--
-- Name: COLUMN presentation_item.file_location; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.presentation_item.file_location IS 'Address of the file. Filled only for an illustration.';


--
-- Name: COLUMN presentation_item.generated_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.presentation_item.generated_at IS 'Moment the element was generated.';


--
-- Name: COLUMN presentation_item.confirmed_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.presentation_item.confirmed_at IS 'Moment the author confirmed the element. NULL while it is pending; until then it is not shown to learners.';


--
-- Name: presentation_item_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.presentation_item ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.presentation_item_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: pronunciation_choice; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.pronunciation_choice (
    id bigint NOT NULL,
    learner_user_id bigint NOT NULL,
    language_id bigint NOT NULL,
    pronunciation_variant_id bigint NOT NULL
);


--
-- Name: TABLE pronunciation_choice; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.pronunciation_choice IS 'Pronunciation variant chosen by a learner for a language. Belongs to the learner, not to a learning link: the choice is the same with every teacher.';


--
-- Name: COLUMN pronunciation_choice.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.pronunciation_choice.id IS 'Surrogate key.';


--
-- Name: COLUMN pronunciation_choice.learner_user_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.pronunciation_choice.learner_user_id IS 'Learner who made the choice.';


--
-- Name: COLUMN pronunciation_choice.language_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.pronunciation_choice.language_id IS 'Language the choice is made for. Repeats the language of the variant so that one choice per language can be enforced.';


--
-- Name: COLUMN pronunciation_choice.pronunciation_variant_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.pronunciation_choice.pronunciation_variant_id IS 'Chosen variant.';


--
-- Name: pronunciation_choice_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.pronunciation_choice ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.pronunciation_choice_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: pronunciation_variant; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.pronunciation_variant (
    id bigint NOT NULL,
    language_id bigint NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    CONSTRAINT ck_pronunciation_variant__code_format CHECK ((code ~ '^[a-z]{2}-[A-Z]{2}$'::text))
);


--
-- Name: TABLE pronunciation_variant; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.pronunciation_variant IS 'Pronunciation variant of a language, for example British and American English. Reference table.';


--
-- Name: COLUMN pronunciation_variant.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.pronunciation_variant.id IS 'Surrogate key.';


--
-- Name: COLUMN pronunciation_variant.language_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.pronunciation_variant.language_id IS 'Language the variant belongs to.';


--
-- Name: COLUMN pronunciation_variant.code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.pronunciation_variant.code IS 'Language and region code, for example en-GB.';


--
-- Name: COLUMN pronunciation_variant.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.pronunciation_variant.name IS 'Variant name.';


--
-- Name: pronunciation_variant_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.pronunciation_variant ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.pronunciation_variant_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: revision_record; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.revision_record (
    id bigint NOT NULL,
    task_id bigint NOT NULL,
    learning_link_id bigint NOT NULL,
    next_revision_date date NOT NULL,
    current_interval_days integer NOT NULL,
    ease numeric(4,2) DEFAULT 2.50 NOT NULL,
    deferred_at timestamp with time zone,
    deferral_end_date date,
    part_id text,
    CONSTRAINT ck_revision_record__ease_min CHECK ((ease >= 1.30)),
    CONSTRAINT ck_revision_record__interval_positive CHECK ((current_interval_days >= 1)),
    CONSTRAINT ck_revision_record__part_id_not_empty CHECK ((part_id <> ''::text))
);


--
-- Name: TABLE revision_record; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.revision_record IS 'Spaced repetition schedule of one task for one learning link.';


--
-- Name: COLUMN revision_record.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.revision_record.id IS 'Surrogate key.';


--
-- Name: COLUMN revision_record.task_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.revision_record.task_id IS 'Task to revise.';


--
-- Name: COLUMN revision_record.learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.revision_record.learning_link_id IS 'Learning link of the learner.';


--
-- Name: COLUMN revision_record.next_revision_date; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.revision_record.next_revision_date IS 'Date of the next revision. The daily queue is built by it.';


--
-- Name: COLUMN revision_record.current_interval_days; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.revision_record.current_interval_days IS 'Current interval in days. Grows after a correct answer.';


--
-- Name: COLUMN revision_record.ease; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.revision_record.ease IS 'Ease factor by which the interval grows after a correct answer.';


--
-- Name: COLUMN revision_record.deferred_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.revision_record.deferred_at IS 'Moment the task was deferred. NULL when it was never deferred. Not cleared when the task returns to the queue.';


--
-- Name: COLUMN revision_record.deferral_end_date; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.revision_record.deferral_end_date IS 'Last day of the deferral. For a self-directed learner the system sets it 7 days ahead; for a learner with a teacher it is NULL until the teacher decides. The task is deferred now when deferred_at is filled and this date is NULL or not yet reached.';


--
-- Name: COLUMN revision_record.part_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.revision_record.part_id IS 'Part of the task, the id from parts in the task body. NULL when the task has one part.';


--
-- Name: revision_record_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.revision_record ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.revision_record_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: scale; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.scale (
    id bigint NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    display_order integer NOT NULL
);


--
-- Name: TABLE scale; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.scale IS 'Skill scale on which a learner level is measured: vocabulary, grammar, writing, speech.';


--
-- Name: COLUMN scale.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.scale.id IS 'Surrogate key.';


--
-- Name: COLUMN scale.code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.scale.code IS 'Stable identifier used by the application. Never changed or translated.';


--
-- Name: COLUMN scale.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.scale.name IS 'Scale name shown to users.';


--
-- Name: COLUMN scale.display_order; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.scale.display_order IS 'Position of the scale in the level chart. The order is always the same.';


--
-- Name: scale_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.scale ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.scale_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: scale_level; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.scale_level (
    id bigint NOT NULL,
    learning_link_id bigint NOT NULL,
    scale_id bigint NOT NULL,
    entry_cefr_level_id bigint,
    current_cefr_level_id bigint
);


--
-- Name: TABLE scale_level; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.scale_level IS 'Level of a learner on one scale within one learning link.';


--
-- Name: COLUMN scale_level.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.scale_level.id IS 'Surrogate key.';


--
-- Name: COLUMN scale_level.learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.scale_level.learning_link_id IS 'Learning link the level belongs to.';


--
-- Name: COLUMN scale_level.scale_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.scale_level.scale_id IS 'Scale.';


--
-- Name: COLUMN scale_level.entry_cefr_level_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.scale_level.entry_cefr_level_id IS 'Level at the start of learning. NULL until set.';


--
-- Name: COLUMN scale_level.current_cefr_level_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.scale_level.current_cefr_level_id IS 'Current level. NULL while there is no data; shown as no data.';


--
-- Name: scale_level_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.scale_level ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.scale_level_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: shown_tooltip; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.shown_tooltip (
    app_user_id bigint NOT NULL,
    interface_element text NOT NULL,
    shown_at timestamp with time zone NOT NULL
);


--
-- Name: TABLE shown_tooltip; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.shown_tooltip IS 'Onboarding tooltip already shown to a user, so that it is not shown again.';


--
-- Name: COLUMN shown_tooltip.app_user_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shown_tooltip.app_user_id IS 'User who saw the tooltip.';


--
-- Name: COLUMN shown_tooltip.interface_element; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shown_tooltip.interface_element IS 'Identifier of the interface element. The list of elements is kept in the application code.';


--
-- Name: COLUMN shown_tooltip.shown_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.shown_tooltip.shown_at IS 'Moment the tooltip was shown.';


--
-- Name: study_group; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.study_group (
    id bigint NOT NULL,
    name text NOT NULL,
    teacher_user_id bigint NOT NULL,
    created_at timestamp with time zone NOT NULL,
    study_language_id bigint NOT NULL
);


--
-- Name: TABLE study_group; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.study_group IS 'Group of learners of one teacher. A group studies one language.';


--
-- Name: COLUMN study_group.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.study_group.id IS 'Surrogate key.';


--
-- Name: COLUMN study_group.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.study_group.name IS 'Group name.';


--
-- Name: COLUMN study_group.teacher_user_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.study_group.teacher_user_id IS 'Teacher who leads the group.';


--
-- Name: COLUMN study_group.created_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.study_group.created_at IS 'Moment of creation.';


--
-- Name: COLUMN study_group.study_language_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.study_group.study_language_id IS 'Language the group studies.';


--
-- Name: study_group_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.study_group ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.study_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: summary_link; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.summary_link (
    id bigint NOT NULL,
    learning_link_id bigint NOT NULL,
    code text NOT NULL,
    created_at timestamp with time zone NOT NULL,
    valid_until timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone
);


--
-- Name: TABLE summary_link; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.summary_link IS 'Read-only link by which a learner shares a summary of own progress.';


--
-- Name: COLUMN summary_link.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.summary_link.id IS 'Surrogate key.';


--
-- Name: COLUMN summary_link.learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.summary_link.learning_link_id IS 'Learning link whose summary is shared.';


--
-- Name: COLUMN summary_link.code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.summary_link.code IS 'Random value used in the address of the link instead of the id.';


--
-- Name: COLUMN summary_link.created_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.summary_link.created_at IS 'Moment the link was created.';


--
-- Name: COLUMN summary_link.valid_until; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.summary_link.valid_until IS 'Moment until which the link works. Set by the learner, 14 days from creation by default.';


--
-- Name: COLUMN summary_link.revoked_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.summary_link.revoked_at IS 'Moment the link was revoked. NULL while it is in force.';


--
-- Name: summary_link_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.summary_link ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.summary_link_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: task; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.task (
    id bigint NOT NULL,
    exercise_id bigint NOT NULL,
    number_in_exercise integer NOT NULL,
    task_text text NOT NULL,
    body jsonb NOT NULL,
    source_page integer NOT NULL,
    position_on_page integer NOT NULL,
    text_audio_location text,
    CONSTRAINT ck_task__number_positive CHECK ((number_in_exercise > 0)),
    CONSTRAINT ck_task__position_positive CHECK ((position_on_page > 0)),
    CONSTRAINT ck_task__source_page_positive CHECK ((source_page > 0))
);


--
-- Name: TABLE task; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.task IS 'Single task of an exercise: the unit a learner answers.';


--
-- Name: COLUMN task.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.task.id IS 'Surrogate key.';


--
-- Name: COLUMN task.exercise_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.task.exercise_id IS 'Exercise the task belongs to.';


--
-- Name: COLUMN task.number_in_exercise; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.task.number_in_exercise IS 'Number of the task inside the exercise. The answer key is matched to the task by it.';


--
-- Name: COLUMN task.task_text; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.task.task_text IS 'Task text, character for character as in the document.';


--
-- Name: COLUMN task.body; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.task.body IS 'Task body: gaps, options, key answers, example flag, highlighted parts. Structure is described in the type catalogue.';


--
-- Name: COLUMN task.source_page; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.task.source_page IS 'Page of the document where the task is.';


--
-- Name: COLUMN task.position_on_page; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.task.position_on_page IS 'Ordinal position of the task on the page, from top to bottom.';


--
-- Name: COLUMN task.text_audio_location; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.task.text_audio_location IS 'Address of the audio file with the task text. NULL until the audio is requested.';


--
-- Name: task_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.task ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.task_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: task_target_word; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.task_target_word (
    task_id bigint NOT NULL,
    word_id bigint NOT NULL
);


--
-- Name: TABLE task_target_word; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.task_target_word IS 'Target word of a single task. Words of a shared word bank are stored in exercise_target_word.';


--
-- Name: COLUMN task_target_word.task_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.task_target_word.task_id IS 'Task.';


--
-- Name: COLUMN task_target_word.word_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.task_target_word.word_id IS 'Target word.';


--
-- Name: topic; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.topic (
    id bigint NOT NULL,
    name text NOT NULL,
    owner_user_id bigint
);


--
-- Name: TABLE topic; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.topic IS 'Topic of exercises: from the common catalogue or created by a user.';


--
-- Name: COLUMN topic.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.topic.id IS 'Surrogate key.';


--
-- Name: COLUMN topic.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.topic.name IS 'Topic name. Unique for one owner and separately within the common catalogue.';


--
-- Name: COLUMN topic.owner_user_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.topic.owner_user_id IS 'User who created the topic. NULL for topics of the common catalogue.';


--
-- Name: topic_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.topic ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.topic_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: topic_priority; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.topic_priority (
    id bigint NOT NULL,
    learning_link_id bigint NOT NULL,
    topic_id bigint NOT NULL,
    raised_at timestamp with time zone NOT NULL,
    end_date date NOT NULL
);


--
-- Name: TABLE topic_priority; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.topic_priority IS 'Raised priority of a topic for a learning link: tasks of the topic come up more often until the end date.';


--
-- Name: COLUMN topic_priority.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.topic_priority.id IS 'Surrogate key.';


--
-- Name: COLUMN topic_priority.learning_link_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.topic_priority.learning_link_id IS 'Learning link the priority is raised for.';


--
-- Name: COLUMN topic_priority.topic_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.topic_priority.topic_id IS 'Topic whose priority is raised.';


--
-- Name: COLUMN topic_priority.raised_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.topic_priority.raised_at IS 'Moment the priority was raised.';


--
-- Name: COLUMN topic_priority.end_date; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.topic_priority.end_date IS 'Last day of the raised priority. Early cancellation is recorded as an end date equal to the current day.';


--
-- Name: topic_priority_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.topic_priority ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.topic_priority_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: v_app_user_masked; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.v_app_user_masked WITH (security_barrier='true') AS
 SELECT id,
    (("left"(email, 1) || '***@'::text) || split_part(email, '@'::text, 2)) AS email_masked,
        CASE
            WHEN (display_name IS NULL) THEN NULL::text
            ELSE ("left"(display_name, 1) || '***'::text)
        END AS display_name_masked,
    country_id,
    age_group,
    registration_role,
    interface_language_id,
    registered_at
   FROM core.app_user u;


--
-- Name: VIEW v_app_user_masked; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON VIEW core.v_app_user_masked IS 'Users with masked personal data: the first character of the e-mail with its domain and the first character of the name.';


--
-- Name: v_material_expiring; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.v_material_expiring AS
 WITH answered AS (
         SELECT a.learning_link_id,
            pr.material_id,
            count(*) AS answers
           FROM (((core.answer a
             JOIN core.task t ON ((t.id = a.task_id)))
             JOIN core.exercise e ON ((e.id = t.exercise_id)))
             JOIN core.parsing_run pr ON ((pr.id = e.parsing_run_id)))
          GROUP BY a.learning_link_id, pr.material_id
        ), revised AS (
         SELECT rr.learning_link_id,
            pr.material_id,
            count(*) AS revision_records
           FROM (((core.revision_record rr
             JOIN core.task t ON ((t.id = rr.task_id)))
             JOIN core.exercise e ON ((e.id = t.exercise_id)))
             JOIN core.parsing_run pr ON ((pr.id = e.parsing_run_id)))
          GROUP BY rr.learning_link_id, pr.material_id
        )
 SELECT ll.id AS learning_link_id,
    ll.learner_user_id,
    m.id AS material_id,
    m.name AS material_name,
    m.retained_until,
    COALESCE(x.answers, (0)::bigint) AS answers,
    COALESCE(x.revision_records, (0)::bigint) AS revision_records
   FROM ((( SELECT learning_link_id,
            material_id,
            answered.answers,
            revised.revision_records
           FROM (answered
             FULL JOIN revised USING (learning_link_id, material_id))) x
     JOIN core.material m ON ((m.id = x.material_id)))
     JOIN core.learning_link ll ON ((ll.id = x.learning_link_id)))
  WHERE (m.retained_until IS NOT NULL);


--
-- Name: VIEW v_material_expiring; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON VIEW core.v_material_expiring IS 'For every learning link: materials of erased owners that will be deleted, the day until which they are kept and how many answers and revision records of the link go with them.';


--
-- Name: v_note_masked; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.v_note_masked WITH (security_barrier='true') AS
 SELECT id,
    learning_link_id,
    lesson_id,
    written_at,
    char_length(note_text) AS note_length
   FROM core.note n;


--
-- Name: VIEW v_note_masked; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON VIEW core.v_note_masked IS 'Notes without their text: only the length of the text is shown.';


--
-- Name: v_revision_queue; Type: VIEW; Schema: core; Owner: -
--

CREATE VIEW core.v_revision_queue AS
 SELECT rr.id AS revision_record_id,
    ll.id AS learning_link_id,
    ll.learner_user_id,
    e.id AS exercise_id,
    t.id AS task_id,
    rr.part_id,
    e.instruction_text,
    t.task_text,
    rr.next_revision_date,
    rr.current_interval_days,
    rr.ease,
    ((now() AT TIME ZONE u.time_zone))::date AS learner_today,
    (rr.next_revision_date <= ((now() AT TIME ZONE u.time_zone))::date) AS is_due,
    ll.access_until AS link_access_until
   FROM ((((core.revision_record rr
     JOIN core.learning_link ll ON ((ll.id = rr.learning_link_id)))
     JOIN core.app_user u ON ((u.id = ll.learner_user_id)))
     JOIN core.task t ON ((t.id = rr.task_id)))
     JOIN core.exercise e ON ((e.id = t.exercise_id)))
  WHERE (((ll.ended_at IS NULL) OR (ll.access_until >= ((now() AT TIME ZONE u.time_zone))::date)) AND (e.excluded_at IS NULL) AND (e.archived_at IS NULL) AND ((rr.deferral_end_date IS NULL) OR (rr.deferral_end_date < ((now() AT TIME ZONE u.time_zone))::date)));


--
-- Name: VIEW v_revision_queue; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON VIEW core.v_revision_queue IS 'Revision records that are not deferred and whose exercise is neither excluded nor archived, for open learning links and for closed links whose access period is not over. is_due tells whether the record is due on the current day of the learner; link_access_until is set for a closed link.';


--
-- Name: visual_style; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.visual_style (
    id bigint NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    display_order integer NOT NULL,
    unlock_closed_scale_count integer,
    CONSTRAINT ck_visual_style__unlock_scale_count_range CHECK (((unlock_closed_scale_count >= 1) AND (unlock_closed_scale_count <= 4)))
);


--
-- Name: TABLE visual_style; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.visual_style IS 'Visual style of the interface. Some styles are available to everyone, others are unlocked as a reward for closed scales.';


--
-- Name: COLUMN visual_style.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.visual_style.id IS 'Surrogate key.';


--
-- Name: COLUMN visual_style.code; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.visual_style.code IS 'Stable identifier used by the application. Never changed or translated.';


--
-- Name: COLUMN visual_style.name; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.visual_style.name IS 'Style name shown to users.';


--
-- Name: COLUMN visual_style.display_order; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.visual_style.display_order IS 'Position of the style in the list.';


--
-- Name: COLUMN visual_style.unlock_closed_scale_count; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.visual_style.unlock_closed_scale_count IS 'Number of scales, from 1 to 4, the learner must have closed to unlock the style. NULL for a style available to everyone.';


--
-- Name: visual_style_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.visual_style ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.visual_style_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: word; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.word (
    id bigint NOT NULL,
    language_id bigint NOT NULL,
    spelling text NOT NULL,
    explanation text,
    reference_requested_at timestamp with time zone
);


--
-- Name: TABLE word; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.word IS 'Word with reference data obtained from external dictionaries and speech synthesis. A result is stored so that a paid service is not asked twice.';


--
-- Name: COLUMN word.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.word.id IS 'Surrogate key.';


--
-- Name: COLUMN word.language_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.word.language_id IS 'Language of the word.';


--
-- Name: COLUMN word.spelling; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.word.spelling IS 'Spelling of the word.';


--
-- Name: COLUMN word.explanation; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.word.explanation IS 'Explanation from a dictionary. NULL when the dictionary has no exact match.';


--
-- Name: COLUMN word.reference_requested_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.word.reference_requested_at IS 'Moment the reference data was requested. NULL when it was never requested. A date with empty reference data means the word was not found.';


--
-- Name: word_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.word ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.word_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: word_pronunciation; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.word_pronunciation (
    id bigint NOT NULL,
    word_id bigint NOT NULL,
    language_id bigint NOT NULL,
    pronunciation_variant_id bigint NOT NULL,
    transcription text,
    audio_location text,
    audio_requested_at timestamp with time zone
);


--
-- Name: TABLE word_pronunciation; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON TABLE core.word_pronunciation IS 'Transcription and audio of a word in one pronunciation variant.';


--
-- Name: COLUMN word_pronunciation.id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.word_pronunciation.id IS 'Surrogate key.';


--
-- Name: COLUMN word_pronunciation.word_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.word_pronunciation.word_id IS 'Word.';


--
-- Name: COLUMN word_pronunciation.language_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.word_pronunciation.language_id IS 'Language of the word and of the variant. Repeats both so that they cannot differ.';


--
-- Name: COLUMN word_pronunciation.pronunciation_variant_id; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.word_pronunciation.pronunciation_variant_id IS 'Pronunciation variant.';


--
-- Name: COLUMN word_pronunciation.transcription; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.word_pronunciation.transcription IS 'Transcription from a dictionary. NULL when the dictionary has no exact match.';


--
-- Name: COLUMN word_pronunciation.audio_location; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.word_pronunciation.audio_location IS 'Address of the audio file. NULL until the audio exists.';


--
-- Name: COLUMN word_pronunciation.audio_requested_at; Type: COMMENT; Schema: core; Owner: -
--

COMMENT ON COLUMN core.word_pronunciation.audio_requested_at IS 'Moment the audio was requested. NULL when it was never requested.';


--
-- Name: word_pronunciation_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

ALTER TABLE core.word_pronunciation ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME core.word_pronunciation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: statistics_event; Type: TABLE; Schema: stats; Owner: -
--

CREATE TABLE stats.statistics_event (
    id bigint NOT NULL,
    link_code uuid NOT NULL,
    exercise_type_id bigint NOT NULL,
    topic_id bigint,
    is_correct boolean NOT NULL,
    attempt_number integer NOT NULL,
    time_bucket text NOT NULL,
    scale_id bigint NOT NULL,
    cefr_level_id bigint NOT NULL,
    device_type text NOT NULL,
    event_date date NOT NULL,
    CONSTRAINT ck_statistics_event__attempt_number_positive CHECK ((attempt_number >= 1)),
    CONSTRAINT ck_statistics_event__device_type CHECK ((device_type = ANY (ARRAY['desktop'::text, 'tablet'::text, 'mobile'::text]))),
    CONSTRAINT ck_statistics_event__time_bucket CHECK ((time_bucket = ANY (ARRAY['fast'::text, 'moderate'::text, 'slow'::text])))
);


--
-- Name: TABLE statistics_event; Type: COMMENT; Schema: stats; Owner: -
--

COMMENT ON TABLE stats.statistics_event IS 'Anonymised event written when a learner answers a task. Contains no personal data and is never updated.';


--
-- Name: COLUMN statistics_event.id; Type: COMMENT; Schema: stats; Owner: -
--

COMMENT ON COLUMN stats.statistics_event.id IS 'Surrogate key.';


--
-- Name: COLUMN statistics_event.link_code; Type: COMMENT; Schema: stats; Owner: -
--

COMMENT ON COLUMN stats.statistics_event.link_code IS 'Random code of the learning link. A plain value, not a reference, so the event survives the erasure of personal data.';


--
-- Name: COLUMN statistics_event.exercise_type_id; Type: COMMENT; Schema: stats; Owner: -
--

COMMENT ON COLUMN stats.statistics_event.exercise_type_id IS 'Exercise type.';


--
-- Name: COLUMN statistics_event.topic_id; Type: COMMENT; Schema: stats; Owner: -
--

COMMENT ON COLUMN stats.statistics_event.topic_id IS 'Topic, only when it is from the common catalogue. NULL for a topic created by a user.';


--
-- Name: COLUMN statistics_event.is_correct; Type: COMMENT; Schema: stats; Owner: -
--

COMMENT ON COLUMN stats.statistics_event.is_correct IS 'True when the answer was correct.';


--
-- Name: COLUMN statistics_event.attempt_number; Type: COMMENT; Schema: stats; Owner: -
--

COMMENT ON COLUMN stats.statistics_event.attempt_number IS 'Number of the attempt.';


--
-- Name: COLUMN statistics_event.time_bucket; Type: COMMENT; Schema: stats; Owner: -
--

COMMENT ON COLUMN stats.statistics_event.time_bucket IS 'Conclusion about speed: fast, moderate or slow. The exact response time is not stored.';


--
-- Name: COLUMN statistics_event.scale_id; Type: COMMENT; Schema: stats; Owner: -
--

COMMENT ON COLUMN stats.statistics_event.scale_id IS 'Scale the exercise trains.';


--
-- Name: COLUMN statistics_event.cefr_level_id; Type: COMMENT; Schema: stats; Owner: -
--

COMMENT ON COLUMN stats.statistics_event.cefr_level_id IS 'Level of the learner on that scale at the moment of the event.';


--
-- Name: COLUMN statistics_event.device_type; Type: COMMENT; Schema: stats; Owner: -
--

COMMENT ON COLUMN stats.statistics_event.device_type IS 'Device type: desktop, tablet or mobile.';


--
-- Name: COLUMN statistics_event.event_date; Type: COMMENT; Schema: stats; Owner: -
--

COMMENT ON COLUMN stats.statistics_event.event_date IS 'Day of the event. The exact time is not stored.';


--
-- Name: mv_statistics_summary; Type: MATERIALIZED VIEW; Schema: stats; Owner: -
--

CREATE MATERIALIZED VIEW stats.mv_statistics_summary AS
 SELECT (date_trunc('month'::text, (event_date)::timestamp with time zone))::date AS month,
    exercise_type_id,
    scale_id,
    cefr_level_id,
    count(*) AS events,
    count(*) FILTER (WHERE is_correct) AS correct_events,
    count(*) FILTER (WHERE (attempt_number = 1)) AS first_attempts,
    count(*) FILTER (WHERE (time_bucket = 'fast'::text)) AS fast_events,
    count(*) FILTER (WHERE (time_bucket = 'slow'::text)) AS slow_events,
    count(DISTINCT link_code) AS learning_links
   FROM stats.statistics_event se
  GROUP BY ((date_trunc('month'::text, (event_date)::timestamp with time zone))::date), exercise_type_id, scale_id, cefr_level_id
  WITH NO DATA;


--
-- Name: MATERIALIZED VIEW mv_statistics_summary; Type: COMMENT; Schema: stats; Owner: -
--

COMMENT ON MATERIALIZED VIEW stats.mv_statistics_summary IS 'Anonymous statistics by month, exercise type, scale and level. Refreshed with stats.refresh_statistics_summary().';


--
-- Name: statistics_event_id_seq; Type: SEQUENCE; Schema: stats; Owner: -
--

ALTER TABLE stats.statistics_event ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME stats.statistics_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: adaptation_proposal pk_adaptation_proposal; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.adaptation_proposal
    ADD CONSTRAINT pk_adaptation_proposal PRIMARY KEY (id);


--
-- Name: adaptation_proposal_item pk_adaptation_proposal_item; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.adaptation_proposal_item
    ADD CONSTRAINT pk_adaptation_proposal_item PRIMARY KEY (id);


--
-- Name: answer pk_answer; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.answer
    ADD CONSTRAINT pk_answer PRIMARY KEY (id);


--
-- Name: app_user pk_app_user; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.app_user
    ADD CONSTRAINT pk_app_user PRIMARY KEY (id);


--
-- Name: cefr_level pk_cefr_level; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.cefr_level
    ADD CONSTRAINT pk_cefr_level PRIMARY KEY (id);


--
-- Name: competition pk_competition; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.competition
    ADD CONSTRAINT pk_competition PRIMARY KEY (id);


--
-- Name: competition_participation pk_competition_participation; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.competition_participation
    ADD CONSTRAINT pk_competition_participation PRIMARY KEY (id);


--
-- Name: consent pk_consent; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.consent
    ADD CONSTRAINT pk_consent PRIMARY KEY (id);


--
-- Name: country pk_country; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.country
    ADD CONSTRAINT pk_country PRIMARY KEY (id);


--
-- Name: course pk_course; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.course
    ADD CONSTRAINT pk_course PRIMARY KEY (id);


--
-- Name: erasure_request pk_erasure_request; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.erasure_request
    ADD CONSTRAINT pk_erasure_request PRIMARY KEY (id);


--
-- Name: error_type pk_error_type; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.error_type
    ADD CONSTRAINT pk_error_type PRIMARY KEY (id);


--
-- Name: exercise pk_exercise; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise
    ADD CONSTRAINT pk_exercise PRIMARY KEY (id);


--
-- Name: exercise_dependency pk_exercise_dependency; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise_dependency
    ADD CONSTRAINT pk_exercise_dependency PRIMARY KEY (id);


--
-- Name: exercise_target_word pk_exercise_target_word; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise_target_word
    ADD CONSTRAINT pk_exercise_target_word PRIMARY KEY (exercise_id, word_id);


--
-- Name: exercise_type pk_exercise_type; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise_type
    ADD CONSTRAINT pk_exercise_type PRIMARY KEY (id);


--
-- Name: exercise_type_compatibility pk_exercise_type_compatibility; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise_type_compatibility
    ADD CONSTRAINT pk_exercise_type_compatibility PRIMARY KEY (id);


--
-- Name: export_request pk_export_request; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.export_request
    ADD CONSTRAINT pk_export_request PRIMARY KEY (id);


--
-- Name: feature_toggle pk_feature_toggle; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.feature_toggle
    ADD CONSTRAINT pk_feature_toggle PRIMARY KEY (id);


--
-- Name: flag pk_flag; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.flag
    ADD CONSTRAINT pk_flag PRIMARY KEY (id);


--
-- Name: flag_reason pk_flag_reason; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.flag_reason
    ADD CONSTRAINT pk_flag_reason PRIMARY KEY (id);


--
-- Name: folder pk_folder; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.folder
    ADD CONSTRAINT pk_folder PRIMARY KEY (id);


--
-- Name: group_membership pk_group_membership; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.group_membership
    ADD CONSTRAINT pk_group_membership PRIMARY KEY (id);


--
-- Name: homework pk_homework; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.homework
    ADD CONSTRAINT pk_homework PRIMARY KEY (id);


--
-- Name: homework_assignment pk_homework_assignment; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.homework_assignment
    ADD CONSTRAINT pk_homework_assignment PRIMARY KEY (id);


--
-- Name: homework_exercise pk_homework_exercise; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.homework_exercise
    ADD CONSTRAINT pk_homework_exercise PRIMARY KEY (homework_id, exercise_id);


--
-- Name: homework_task pk_homework_task; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.homework_task
    ADD CONSTRAINT pk_homework_task PRIMARY KEY (homework_id, task_id);


--
-- Name: image pk_image; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.image
    ADD CONSTRAINT pk_image PRIMARY KEY (id);


--
-- Name: invitation pk_invitation; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.invitation
    ADD CONSTRAINT pk_invitation PRIMARY KEY (id);


--
-- Name: language pk_language; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.language
    ADD CONSTRAINT pk_language PRIMARY KEY (id);


--
-- Name: learning_link pk_learning_link; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.learning_link
    ADD CONSTRAINT pk_learning_link PRIMARY KEY (id);


--
-- Name: learning_link_pseudonym pk_learning_link_pseudonym; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.learning_link_pseudonym
    ADD CONSTRAINT pk_learning_link_pseudonym PRIMARY KEY (id);


--
-- Name: lesson pk_lesson; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.lesson
    ADD CONSTRAINT pk_lesson PRIMARY KEY (id);


--
-- Name: lesson_exercise pk_lesson_exercise; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.lesson_exercise
    ADD CONSTRAINT pk_lesson_exercise PRIMARY KEY (id);


--
-- Name: level_change pk_level_change; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.level_change
    ADD CONSTRAINT pk_level_change PRIMARY KEY (id);


--
-- Name: material pk_material; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.material
    ADD CONSTRAINT pk_material PRIMARY KEY (id);


--
-- Name: note pk_note; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.note
    ADD CONSTRAINT pk_note PRIMARY KEY (id);


--
-- Name: oral_error pk_oral_error; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.oral_error
    ADD CONSTRAINT pk_oral_error PRIMARY KEY (id);


--
-- Name: parsing_run pk_parsing_run; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.parsing_run
    ADD CONSTRAINT pk_parsing_run PRIMARY KEY (id);


--
-- Name: policy_version pk_policy_version; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.policy_version
    ADD CONSTRAINT pk_policy_version PRIMARY KEY (id);


--
-- Name: presentation_item pk_presentation_item; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.presentation_item
    ADD CONSTRAINT pk_presentation_item PRIMARY KEY (id);


--
-- Name: pronunciation_choice pk_pronunciation_choice; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pronunciation_choice
    ADD CONSTRAINT pk_pronunciation_choice PRIMARY KEY (id);


--
-- Name: pronunciation_variant pk_pronunciation_variant; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pronunciation_variant
    ADD CONSTRAINT pk_pronunciation_variant PRIMARY KEY (id);


--
-- Name: revision_record pk_revision_record; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.revision_record
    ADD CONSTRAINT pk_revision_record PRIMARY KEY (id);


--
-- Name: scale pk_scale; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.scale
    ADD CONSTRAINT pk_scale PRIMARY KEY (id);


--
-- Name: scale_level pk_scale_level; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.scale_level
    ADD CONSTRAINT pk_scale_level PRIMARY KEY (id);


--
-- Name: shown_tooltip pk_shown_tooltip; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.shown_tooltip
    ADD CONSTRAINT pk_shown_tooltip PRIMARY KEY (app_user_id, interface_element);


--
-- Name: study_group pk_study_group; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.study_group
    ADD CONSTRAINT pk_study_group PRIMARY KEY (id);


--
-- Name: summary_link pk_summary_link; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.summary_link
    ADD CONSTRAINT pk_summary_link PRIMARY KEY (id);


--
-- Name: task pk_task; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.task
    ADD CONSTRAINT pk_task PRIMARY KEY (id);


--
-- Name: task_target_word pk_task_target_word; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.task_target_word
    ADD CONSTRAINT pk_task_target_word PRIMARY KEY (task_id, word_id);


--
-- Name: topic pk_topic; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.topic
    ADD CONSTRAINT pk_topic PRIMARY KEY (id);


--
-- Name: topic_priority pk_topic_priority; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.topic_priority
    ADD CONSTRAINT pk_topic_priority PRIMARY KEY (id);


--
-- Name: visual_style pk_visual_style; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.visual_style
    ADD CONSTRAINT pk_visual_style PRIMARY KEY (id);


--
-- Name: word pk_word; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.word
    ADD CONSTRAINT pk_word PRIMARY KEY (id);


--
-- Name: word_pronunciation pk_word_pronunciation; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.word_pronunciation
    ADD CONSTRAINT pk_word_pronunciation PRIMARY KEY (id);


--
-- Name: adaptation_proposal_item uq_adaptation_proposal_item__pair; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.adaptation_proposal_item
    ADD CONSTRAINT uq_adaptation_proposal_item__pair UNIQUE (adaptation_proposal_id, exercise_id);


--
-- Name: app_user uq_app_user__email; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.app_user
    ADD CONSTRAINT uq_app_user__email UNIQUE (email);


--
-- Name: cefr_level uq_cefr_level__name; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.cefr_level
    ADD CONSTRAINT uq_cefr_level__name UNIQUE (name);


--
-- Name: cefr_level uq_cefr_level__sort_order; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.cefr_level
    ADD CONSTRAINT uq_cefr_level__sort_order UNIQUE (sort_order);


--
-- Name: competition_participation uq_competition_participation__nickname; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.competition_participation
    ADD CONSTRAINT uq_competition_participation__nickname UNIQUE (competition_id, nickname);


--
-- Name: competition_participation uq_competition_participation__pair; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.competition_participation
    ADD CONSTRAINT uq_competition_participation__pair UNIQUE (competition_id, learning_link_id);


--
-- Name: country uq_country__code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.country
    ADD CONSTRAINT uq_country__code UNIQUE (code);


--
-- Name: error_type uq_error_type__code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.error_type
    ADD CONSTRAINT uq_error_type__code UNIQUE (code);


--
-- Name: error_type uq_error_type__name; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.error_type
    ADD CONSTRAINT uq_error_type__name UNIQUE (name);


--
-- Name: exercise_dependency uq_exercise_dependency__pair; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise_dependency
    ADD CONSTRAINT uq_exercise_dependency__pair UNIQUE (dependent_exercise_id, prerequisite_exercise_id);


--
-- Name: exercise_type uq_exercise_type__code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise_type
    ADD CONSTRAINT uq_exercise_type__code UNIQUE (code);


--
-- Name: exercise_type uq_exercise_type__name; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise_type
    ADD CONSTRAINT uq_exercise_type__name UNIQUE (name);


--
-- Name: exercise_type_compatibility uq_exercise_type_compatibility__pair; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise_type_compatibility
    ADD CONSTRAINT uq_exercise_type_compatibility__pair UNIQUE (source_type_id, target_type_id);


--
-- Name: feature_toggle uq_feature_toggle__group_feature; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.feature_toggle
    ADD CONSTRAINT uq_feature_toggle__group_feature UNIQUE (study_group_id, feature);


--
-- Name: feature_toggle uq_feature_toggle__link_feature; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.feature_toggle
    ADD CONSTRAINT uq_feature_toggle__link_feature UNIQUE (learning_link_id, feature);


--
-- Name: flag_reason uq_flag_reason__code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.flag_reason
    ADD CONSTRAINT uq_flag_reason__code UNIQUE (code);


--
-- Name: flag_reason uq_flag_reason__name; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.flag_reason
    ADD CONSTRAINT uq_flag_reason__name UNIQUE (name);


--
-- Name: homework_assignment uq_homework_assignment__pair; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.homework_assignment
    ADD CONSTRAINT uq_homework_assignment__pair UNIQUE (homework_id, learning_link_id);


--
-- Name: homework_exercise uq_homework_exercise__order; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.homework_exercise
    ADD CONSTRAINT uq_homework_exercise__order UNIQUE (homework_id, sort_order);


--
-- Name: homework_task uq_homework_task__order; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.homework_task
    ADD CONSTRAINT uq_homework_task__order UNIQUE (homework_id, sort_order);


--
-- Name: invitation uq_invitation__code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.invitation
    ADD CONSTRAINT uq_invitation__code UNIQUE (code);


--
-- Name: language uq_language__code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.language
    ADD CONSTRAINT uq_language__code UNIQUE (code);


--
-- Name: language uq_language__name; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.language
    ADD CONSTRAINT uq_language__name UNIQUE (name);


--
-- Name: learning_link uq_learning_link__course; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.learning_link
    ADD CONSTRAINT uq_learning_link__course UNIQUE (course_id);


--
-- Name: learning_link_pseudonym uq_learning_link_pseudonym__code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.learning_link_pseudonym
    ADD CONSTRAINT uq_learning_link_pseudonym__code UNIQUE (random_code);


--
-- Name: learning_link_pseudonym uq_learning_link_pseudonym__link; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.learning_link_pseudonym
    ADD CONSTRAINT uq_learning_link_pseudonym__link UNIQUE (learning_link_id);


--
-- Name: policy_version uq_policy_version__version_number; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.policy_version
    ADD CONSTRAINT uq_policy_version__version_number UNIQUE (version_number);


--
-- Name: pronunciation_choice uq_pronunciation_choice__learner_language; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pronunciation_choice
    ADD CONSTRAINT uq_pronunciation_choice__learner_language UNIQUE (learner_user_id, language_id);


--
-- Name: pronunciation_variant uq_pronunciation_variant__code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pronunciation_variant
    ADD CONSTRAINT uq_pronunciation_variant__code UNIQUE (code);


--
-- Name: pronunciation_variant uq_pronunciation_variant__id_and_language; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pronunciation_variant
    ADD CONSTRAINT uq_pronunciation_variant__id_and_language UNIQUE (id, language_id);


--
-- Name: pronunciation_variant uq_pronunciation_variant__language_name; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pronunciation_variant
    ADD CONSTRAINT uq_pronunciation_variant__language_name UNIQUE (language_id, name);


--
-- Name: revision_record uq_revision_record__link_task_part; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.revision_record
    ADD CONSTRAINT uq_revision_record__link_task_part UNIQUE NULLS NOT DISTINCT (learning_link_id, task_id, part_id);


--
-- Name: scale uq_scale__code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.scale
    ADD CONSTRAINT uq_scale__code UNIQUE (code);


--
-- Name: scale uq_scale__display_order; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.scale
    ADD CONSTRAINT uq_scale__display_order UNIQUE (display_order);


--
-- Name: scale uq_scale__name; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.scale
    ADD CONSTRAINT uq_scale__name UNIQUE (name);


--
-- Name: scale_level uq_scale_level__pair; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.scale_level
    ADD CONSTRAINT uq_scale_level__pair UNIQUE (learning_link_id, scale_id);


--
-- Name: summary_link uq_summary_link__code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.summary_link
    ADD CONSTRAINT uq_summary_link__code UNIQUE (code);


--
-- Name: task uq_task__exercise_number; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.task
    ADD CONSTRAINT uq_task__exercise_number UNIQUE (exercise_id, number_in_exercise);


--
-- Name: topic uq_topic__owner_name; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.topic
    ADD CONSTRAINT uq_topic__owner_name UNIQUE (owner_user_id, name);


--
-- Name: visual_style uq_visual_style__code; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.visual_style
    ADD CONSTRAINT uq_visual_style__code UNIQUE (code);


--
-- Name: visual_style uq_visual_style__display_order; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.visual_style
    ADD CONSTRAINT uq_visual_style__display_order UNIQUE (display_order);


--
-- Name: visual_style uq_visual_style__name; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.visual_style
    ADD CONSTRAINT uq_visual_style__name UNIQUE (name);


--
-- Name: word uq_word__id_and_language; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.word
    ADD CONSTRAINT uq_word__id_and_language UNIQUE (id, language_id);


--
-- Name: word uq_word__language_spelling; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.word
    ADD CONSTRAINT uq_word__language_spelling UNIQUE (language_id, spelling);


--
-- Name: word_pronunciation uq_word_pronunciation__word_variant; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.word_pronunciation
    ADD CONSTRAINT uq_word_pronunciation__word_variant UNIQUE (word_id, pronunciation_variant_id);


--
-- Name: statistics_event pk_statistics_event; Type: CONSTRAINT; Schema: stats; Owner: -
--

ALTER TABLE ONLY stats.statistics_event
    ADD CONSTRAINT pk_statistics_event PRIMARY KEY (id);


--
-- Name: ix_adaptation_proposal__learning_link; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_adaptation_proposal__learning_link ON core.adaptation_proposal USING btree (learning_link_id);


--
-- Name: ix_adaptation_proposal_item__exercise; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_adaptation_proposal_item__exercise ON core.adaptation_proposal_item USING btree (exercise_id);


--
-- Name: ix_adaptation_proposal_item__rationale_topic; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_adaptation_proposal_item__rationale_topic ON core.adaptation_proposal_item USING btree (rationale_topic_id);


--
-- Name: ix_answer__competition_participation; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_answer__competition_participation ON core.answer USING btree (competition_participation_id);


--
-- Name: ix_answer__homework_assignment; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_answer__homework_assignment ON core.answer USING btree (homework_assignment_id);


--
-- Name: ix_answer__learning_link_answered_at; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_answer__learning_link_answered_at ON core.answer USING btree (learning_link_id, answered_at);


--
-- Name: ix_answer__lesson_exercise; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_answer__lesson_exercise ON core.answer USING btree (lesson_exercise_id);


--
-- Name: ix_answer__task; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_answer__task ON core.answer USING btree (task_id);


--
-- Name: ix_competition__exercise; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_competition__exercise ON core.competition USING btree (exercise_id);


--
-- Name: ix_competition__lesson; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_competition__lesson ON core.competition USING btree (lesson_id);


--
-- Name: ix_competition_participation__learning_link; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_competition_participation__learning_link ON core.competition_participation USING btree (learning_link_id);


--
-- Name: ix_consent__app_user; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_consent__app_user ON core.consent USING btree (app_user_id);


--
-- Name: ix_course__owner_user; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_course__owner_user ON core.course USING btree (owner_user_id);


--
-- Name: ix_erasure_request__app_user; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_erasure_request__app_user ON core.erasure_request USING btree (app_user_id);


--
-- Name: ix_erasure_request__learning_link; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_erasure_request__learning_link ON core.erasure_request USING btree (learning_link_id);


--
-- Name: ix_exercise__parsing_run; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_exercise__parsing_run ON core.exercise USING btree (parsing_run_id);


--
-- Name: ix_exercise__source_exercise; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_exercise__source_exercise ON core.exercise USING btree (source_exercise_id);


--
-- Name: ix_exercise__topic; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_exercise__topic ON core.exercise USING btree (topic_id);


--
-- Name: ix_exercise_dependency__prerequisite_exercise; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_exercise_dependency__prerequisite_exercise ON core.exercise_dependency USING btree (prerequisite_exercise_id);


--
-- Name: ix_exercise_target_word__word; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_exercise_target_word__word ON core.exercise_target_word USING btree (word_id);


--
-- Name: ix_export_request__app_user; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_export_request__app_user ON core.export_request USING btree (app_user_id);


--
-- Name: ix_export_request__learning_link; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_export_request__learning_link ON core.export_request USING btree (learning_link_id);


--
-- Name: ix_flag__exercise; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_flag__exercise ON core.flag USING btree (exercise_id);


--
-- Name: ix_flag__placed_by_user; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_flag__placed_by_user ON core.flag USING btree (placed_by_user_id);


--
-- Name: ix_flag__task; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_flag__task ON core.flag USING btree (task_id);


--
-- Name: ix_folder__owner_user; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_folder__owner_user ON core.folder USING btree (owner_user_id);


--
-- Name: ix_folder__parent_folder; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_folder__parent_folder ON core.folder USING btree (parent_folder_id);


--
-- Name: ix_group_membership__learning_link; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_group_membership__learning_link ON core.group_membership USING btree (learning_link_id);


--
-- Name: ix_group_membership__study_group; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_group_membership__study_group ON core.group_membership USING btree (study_group_id);


--
-- Name: ix_homework__adaptation_proposal; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_homework__adaptation_proposal ON core.homework USING btree (adaptation_proposal_id);


--
-- Name: ix_homework__assigned_by_user; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_homework__assigned_by_user ON core.homework USING btree (assigned_by_user_id);


--
-- Name: ix_homework__study_group; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_homework__study_group ON core.homework USING btree (study_group_id);


--
-- Name: ix_homework_assignment__learning_link; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_homework_assignment__learning_link ON core.homework_assignment USING btree (learning_link_id);


--
-- Name: ix_homework_exercise__exercise; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_homework_exercise__exercise ON core.homework_exercise USING btree (exercise_id);


--
-- Name: ix_homework_task__task; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_homework_task__task ON core.homework_task USING btree (task_id);


--
-- Name: ix_image__exercise; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_image__exercise ON core.image USING btree (exercise_id);


--
-- Name: ix_image__source_image; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_image__source_image ON core.image USING btree (source_image_id);


--
-- Name: ix_image__task; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_image__task ON core.image USING btree (task_id);


--
-- Name: ix_invitation__study_group; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_invitation__study_group ON core.invitation USING btree (study_group_id);


--
-- Name: ix_learning_link__learner_user; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_learning_link__learner_user ON core.learning_link USING btree (learner_user_id);


--
-- Name: ix_learning_link__teacher_user; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_learning_link__teacher_user ON core.learning_link USING btree (teacher_user_id);


--
-- Name: ix_lesson__learning_link; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_lesson__learning_link ON core.lesson USING btree (learning_link_id);


--
-- Name: ix_lesson__study_group; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_lesson__study_group ON core.lesson USING btree (study_group_id);


--
-- Name: ix_lesson_exercise__exercise; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_lesson_exercise__exercise ON core.lesson_exercise USING btree (exercise_id);


--
-- Name: ix_lesson_exercise__lesson; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_lesson_exercise__lesson ON core.lesson_exercise USING btree (lesson_id);


--
-- Name: ix_lesson_exercise__shown_to_learning_link; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_lesson_exercise__shown_to_learning_link ON core.lesson_exercise USING btree (shown_to_learning_link_id);


--
-- Name: ix_level_change__scale_level; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_level_change__scale_level ON core.level_change USING btree (scale_level_id);


--
-- Name: ix_material__course; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_material__course ON core.material USING btree (course_id);


--
-- Name: ix_material__folder; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_material__folder ON core.material USING btree (folder_id);


--
-- Name: ix_material__owner_user; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_material__owner_user ON core.material USING btree (owner_user_id);


--
-- Name: ix_material__retained_until; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_material__retained_until ON core.material USING btree (retained_until) WHERE (retained_until IS NOT NULL);


--
-- Name: ix_note__learning_link; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_note__learning_link ON core.note USING btree (learning_link_id);


--
-- Name: ix_note__lesson; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_note__lesson ON core.note USING btree (lesson_id);


--
-- Name: ix_oral_error__learning_link; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_oral_error__learning_link ON core.oral_error USING btree (learning_link_id);


--
-- Name: ix_oral_error__lesson; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_oral_error__lesson ON core.oral_error USING btree (lesson_id);


--
-- Name: ix_oral_error__task; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_oral_error__task ON core.oral_error USING btree (task_id);


--
-- Name: ix_oral_error__topic; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_oral_error__topic ON core.oral_error USING btree (topic_id);


--
-- Name: ix_parsing_run__material; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_parsing_run__material ON core.parsing_run USING btree (material_id);


--
-- Name: ix_presentation_item__exercise; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_presentation_item__exercise ON core.presentation_item USING btree (exercise_id);


--
-- Name: ix_presentation_item__task; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_presentation_item__task ON core.presentation_item USING btree (task_id);


--
-- Name: ix_revision_record__link_next_date; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_revision_record__link_next_date ON core.revision_record USING btree (learning_link_id, next_revision_date);


--
-- Name: ix_revision_record__task; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_revision_record__task ON core.revision_record USING btree (task_id);


--
-- Name: ix_study_group__teacher_user; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_study_group__teacher_user ON core.study_group USING btree (teacher_user_id);


--
-- Name: ix_summary_link__learning_link; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_summary_link__learning_link ON core.summary_link USING btree (learning_link_id);


--
-- Name: ix_task_target_word__word; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_task_target_word__word ON core.task_target_word USING btree (word_id);


--
-- Name: ix_topic_priority__learning_link; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_topic_priority__learning_link ON core.topic_priority USING btree (learning_link_id);


--
-- Name: ix_topic_priority__topic; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX ix_topic_priority__topic ON core.topic_priority USING btree (topic_id);


--
-- Name: uq_consent__active; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX uq_consent__active ON core.consent USING btree (app_user_id, consent_kind) WHERE (withdrawn_at IS NULL);


--
-- Name: uq_group_membership__active; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX uq_group_membership__active ON core.group_membership USING btree (learning_link_id, study_group_id) WHERE (left_at IS NULL);


--
-- Name: uq_learning_link__open_self_directed; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX uq_learning_link__open_self_directed ON core.learning_link USING btree (learner_user_id, study_language_id) WHERE ((link_kind = 'self_directed'::text) AND (ended_at IS NULL));


--
-- Name: uq_learning_link__open_triple; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX uq_learning_link__open_triple ON core.learning_link USING btree (learner_user_id, teacher_user_id, study_language_id) WHERE (ended_at IS NULL);


--
-- Name: uq_material__folder_part; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX uq_material__folder_part ON core.material USING btree (folder_id, part_number) WHERE (part_number IS NOT NULL);


--
-- Name: uq_topic__catalogue_name; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX uq_topic__catalogue_name ON core.topic USING btree (name) WHERE (owner_user_id IS NULL);


--
-- Name: ix_statistics_event__event_date; Type: INDEX; Schema: stats; Owner: -
--

CREATE INDEX ix_statistics_event__event_date ON stats.statistics_event USING btree (event_date);


--
-- Name: ix_statistics_event__link_code; Type: INDEX; Schema: stats; Owner: -
--

CREATE INDEX ix_statistics_event__link_code ON stats.statistics_event USING btree (link_code);


--
-- Name: ix_statistics_event__topic; Type: INDEX; Schema: stats; Owner: -
--

CREATE INDEX ix_statistics_event__topic ON stats.statistics_event USING btree (topic_id);


--
-- Name: uq_mv_statistics_summary__key; Type: INDEX; Schema: stats; Owner: -
--

CREATE UNIQUE INDEX uq_mv_statistics_summary__key ON stats.mv_statistics_summary USING btree (month, exercise_type_id, scale_id, cefr_level_id);


--
-- Name: scale_level trg_scale_level__log_level_change; Type: TRIGGER; Schema: core; Owner: -
--

CREATE TRIGGER trg_scale_level__log_level_change AFTER UPDATE OF current_cefr_level_id ON core.scale_level FOR EACH ROW WHEN (((old.current_cefr_level_id IS NOT NULL) AND (new.current_cefr_level_id IS NOT NULL) AND (old.current_cefr_level_id <> new.current_cefr_level_id))) EXECUTE FUNCTION core.log_level_change();


--
-- Name: adaptation_proposal fk_adaptation_proposal__learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.adaptation_proposal
    ADD CONSTRAINT fk_adaptation_proposal__learning_link FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE;


--
-- Name: adaptation_proposal_item fk_adaptation_proposal_item__adaptation_proposal; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.adaptation_proposal_item
    ADD CONSTRAINT fk_adaptation_proposal_item__adaptation_proposal FOREIGN KEY (adaptation_proposal_id) REFERENCES core.adaptation_proposal(id) ON DELETE CASCADE;


--
-- Name: adaptation_proposal_item fk_adaptation_proposal_item__exercise; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.adaptation_proposal_item
    ADD CONSTRAINT fk_adaptation_proposal_item__exercise FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE;


--
-- Name: adaptation_proposal_item fk_adaptation_proposal_item__rationale_topic; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.adaptation_proposal_item
    ADD CONSTRAINT fk_adaptation_proposal_item__rationale_topic FOREIGN KEY (rationale_topic_id) REFERENCES core.topic(id) ON DELETE SET NULL;


--
-- Name: adaptation_proposal_item fk_adaptation_proposal_item__shown_as_exercise_type; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.adaptation_proposal_item
    ADD CONSTRAINT fk_adaptation_proposal_item__shown_as_exercise_type FOREIGN KEY (shown_as_exercise_type_id) REFERENCES core.exercise_type(id) ON DELETE RESTRICT;


--
-- Name: answer fk_answer__competition_participation; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.answer
    ADD CONSTRAINT fk_answer__competition_participation FOREIGN KEY (competition_participation_id) REFERENCES core.competition_participation(id) ON DELETE SET NULL;


--
-- Name: answer fk_answer__error_type; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.answer
    ADD CONSTRAINT fk_answer__error_type FOREIGN KEY (error_type_id) REFERENCES core.error_type(id) ON DELETE RESTRICT;


--
-- Name: answer fk_answer__homework_assignment; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.answer
    ADD CONSTRAINT fk_answer__homework_assignment FOREIGN KEY (homework_assignment_id) REFERENCES core.homework_assignment(id) ON DELETE SET NULL;


--
-- Name: answer fk_answer__learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.answer
    ADD CONSTRAINT fk_answer__learning_link FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE;


--
-- Name: answer fk_answer__lesson_exercise; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.answer
    ADD CONSTRAINT fk_answer__lesson_exercise FOREIGN KEY (lesson_exercise_id) REFERENCES core.lesson_exercise(id) ON DELETE SET NULL;


--
-- Name: answer fk_answer__shown_as_exercise_type; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.answer
    ADD CONSTRAINT fk_answer__shown_as_exercise_type FOREIGN KEY (shown_as_exercise_type_id) REFERENCES core.exercise_type(id) ON DELETE RESTRICT;


--
-- Name: answer fk_answer__task; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.answer
    ADD CONSTRAINT fk_answer__task FOREIGN KEY (task_id) REFERENCES core.task(id) ON DELETE CASCADE;


--
-- Name: app_user fk_app_user__country; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.app_user
    ADD CONSTRAINT fk_app_user__country FOREIGN KEY (country_id) REFERENCES core.country(id) ON DELETE RESTRICT;


--
-- Name: app_user fk_app_user__interface_language; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.app_user
    ADD CONSTRAINT fk_app_user__interface_language FOREIGN KEY (interface_language_id) REFERENCES core.language(id) ON DELETE RESTRICT;


--
-- Name: app_user fk_app_user__visual_style; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.app_user
    ADD CONSTRAINT fk_app_user__visual_style FOREIGN KEY (visual_style_id) REFERENCES core.visual_style(id) ON DELETE SET NULL;


--
-- Name: competition fk_competition__cefr_level; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.competition
    ADD CONSTRAINT fk_competition__cefr_level FOREIGN KEY (cefr_level_id) REFERENCES core.cefr_level(id) ON DELETE RESTRICT;


--
-- Name: competition fk_competition__exercise; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.competition
    ADD CONSTRAINT fk_competition__exercise FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE;


--
-- Name: competition fk_competition__exercise_type; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.competition
    ADD CONSTRAINT fk_competition__exercise_type FOREIGN KEY (exercise_type_id) REFERENCES core.exercise_type(id) ON DELETE RESTRICT;


--
-- Name: competition fk_competition__lesson; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.competition
    ADD CONSTRAINT fk_competition__lesson FOREIGN KEY (lesson_id) REFERENCES core.lesson(id) ON DELETE CASCADE;


--
-- Name: competition fk_competition__scale; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.competition
    ADD CONSTRAINT fk_competition__scale FOREIGN KEY (scale_id) REFERENCES core.scale(id) ON DELETE RESTRICT;


--
-- Name: competition_participation fk_competition_participation__competition; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.competition_participation
    ADD CONSTRAINT fk_competition_participation__competition FOREIGN KEY (competition_id) REFERENCES core.competition(id) ON DELETE CASCADE;


--
-- Name: competition_participation fk_competition_participation__learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.competition_participation
    ADD CONSTRAINT fk_competition_participation__learning_link FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE;


--
-- Name: consent fk_consent__app_user; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.consent
    ADD CONSTRAINT fk_consent__app_user FOREIGN KEY (app_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE;


--
-- Name: consent fk_consent__policy_version; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.consent
    ADD CONSTRAINT fk_consent__policy_version FOREIGN KEY (policy_version_id) REFERENCES core.policy_version(id) ON DELETE RESTRICT;


--
-- Name: course fk_course__owner_user; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.course
    ADD CONSTRAINT fk_course__owner_user FOREIGN KEY (owner_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE;


--
-- Name: erasure_request fk_erasure_request__app_user; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.erasure_request
    ADD CONSTRAINT fk_erasure_request__app_user FOREIGN KEY (app_user_id) REFERENCES core.app_user(id) ON DELETE SET NULL;


--
-- Name: erasure_request fk_erasure_request__learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.erasure_request
    ADD CONSTRAINT fk_erasure_request__learning_link FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE SET NULL;


--
-- Name: exercise fk_exercise__exercise_type; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise
    ADD CONSTRAINT fk_exercise__exercise_type FOREIGN KEY (exercise_type_id) REFERENCES core.exercise_type(id) ON DELETE RESTRICT;


--
-- Name: exercise fk_exercise__parsing_run; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise
    ADD CONSTRAINT fk_exercise__parsing_run FOREIGN KEY (parsing_run_id) REFERENCES core.parsing_run(id) ON DELETE CASCADE;


--
-- Name: exercise fk_exercise__scale; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise
    ADD CONSTRAINT fk_exercise__scale FOREIGN KEY (scale_id) REFERENCES core.scale(id) ON DELETE RESTRICT;


--
-- Name: exercise fk_exercise__source_exercise; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise
    ADD CONSTRAINT fk_exercise__source_exercise FOREIGN KEY (source_exercise_id) REFERENCES core.exercise(id) ON DELETE SET NULL;


--
-- Name: exercise fk_exercise__topic; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise
    ADD CONSTRAINT fk_exercise__topic FOREIGN KEY (topic_id) REFERENCES core.topic(id) ON DELETE RESTRICT;


--
-- Name: exercise_dependency fk_exercise_dependency__dependent_exercise; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise_dependency
    ADD CONSTRAINT fk_exercise_dependency__dependent_exercise FOREIGN KEY (dependent_exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE;


--
-- Name: exercise_dependency fk_exercise_dependency__prerequisite_exercise; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise_dependency
    ADD CONSTRAINT fk_exercise_dependency__prerequisite_exercise FOREIGN KEY (prerequisite_exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE;


--
-- Name: exercise_target_word fk_exercise_target_word__exercise; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise_target_word
    ADD CONSTRAINT fk_exercise_target_word__exercise FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE;


--
-- Name: exercise_target_word fk_exercise_target_word__word; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise_target_word
    ADD CONSTRAINT fk_exercise_target_word__word FOREIGN KEY (word_id) REFERENCES core.word(id) ON DELETE RESTRICT;


--
-- Name: exercise_type_compatibility fk_exercise_type_compatibility__source_type; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise_type_compatibility
    ADD CONSTRAINT fk_exercise_type_compatibility__source_type FOREIGN KEY (source_type_id) REFERENCES core.exercise_type(id) ON DELETE CASCADE;


--
-- Name: exercise_type_compatibility fk_exercise_type_compatibility__target_type; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.exercise_type_compatibility
    ADD CONSTRAINT fk_exercise_type_compatibility__target_type FOREIGN KEY (target_type_id) REFERENCES core.exercise_type(id) ON DELETE CASCADE;


--
-- Name: export_request fk_export_request__app_user; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.export_request
    ADD CONSTRAINT fk_export_request__app_user FOREIGN KEY (app_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE;


--
-- Name: export_request fk_export_request__learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.export_request
    ADD CONSTRAINT fk_export_request__learning_link FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE;


--
-- Name: feature_toggle fk_feature_toggle__learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.feature_toggle
    ADD CONSTRAINT fk_feature_toggle__learning_link FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE;


--
-- Name: feature_toggle fk_feature_toggle__study_group; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.feature_toggle
    ADD CONSTRAINT fk_feature_toggle__study_group FOREIGN KEY (study_group_id) REFERENCES core.study_group(id) ON DELETE CASCADE;


--
-- Name: flag fk_flag__exercise; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.flag
    ADD CONSTRAINT fk_flag__exercise FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE;


--
-- Name: flag fk_flag__flag_reason; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.flag
    ADD CONSTRAINT fk_flag__flag_reason FOREIGN KEY (flag_reason_id) REFERENCES core.flag_reason(id) ON DELETE RESTRICT;


--
-- Name: flag fk_flag__placed_by_user; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.flag
    ADD CONSTRAINT fk_flag__placed_by_user FOREIGN KEY (placed_by_user_id) REFERENCES core.app_user(id) ON DELETE SET NULL;


--
-- Name: flag fk_flag__task; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.flag
    ADD CONSTRAINT fk_flag__task FOREIGN KEY (task_id) REFERENCES core.task(id) ON DELETE CASCADE;


--
-- Name: folder fk_folder__owner_user; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.folder
    ADD CONSTRAINT fk_folder__owner_user FOREIGN KEY (owner_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE;


--
-- Name: folder fk_folder__parent_folder; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.folder
    ADD CONSTRAINT fk_folder__parent_folder FOREIGN KEY (parent_folder_id) REFERENCES core.folder(id) ON DELETE RESTRICT;


--
-- Name: group_membership fk_group_membership__learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.group_membership
    ADD CONSTRAINT fk_group_membership__learning_link FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE;


--
-- Name: group_membership fk_group_membership__study_group; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.group_membership
    ADD CONSTRAINT fk_group_membership__study_group FOREIGN KEY (study_group_id) REFERENCES core.study_group(id) ON DELETE CASCADE;


--
-- Name: homework fk_homework__adaptation_proposal; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.homework
    ADD CONSTRAINT fk_homework__adaptation_proposal FOREIGN KEY (adaptation_proposal_id) REFERENCES core.adaptation_proposal(id) ON DELETE SET NULL;


--
-- Name: homework fk_homework__assigned_by_user; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.homework
    ADD CONSTRAINT fk_homework__assigned_by_user FOREIGN KEY (assigned_by_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE;


--
-- Name: homework fk_homework__study_group; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.homework
    ADD CONSTRAINT fk_homework__study_group FOREIGN KEY (study_group_id) REFERENCES core.study_group(id) ON DELETE CASCADE;


--
-- Name: homework_assignment fk_homework_assignment__homework; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.homework_assignment
    ADD CONSTRAINT fk_homework_assignment__homework FOREIGN KEY (homework_id) REFERENCES core.homework(id) ON DELETE CASCADE;


--
-- Name: homework_assignment fk_homework_assignment__learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.homework_assignment
    ADD CONSTRAINT fk_homework_assignment__learning_link FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE;


--
-- Name: homework_exercise fk_homework_exercise__exercise; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.homework_exercise
    ADD CONSTRAINT fk_homework_exercise__exercise FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE;


--
-- Name: homework_exercise fk_homework_exercise__homework; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.homework_exercise
    ADD CONSTRAINT fk_homework_exercise__homework FOREIGN KEY (homework_id) REFERENCES core.homework(id) ON DELETE CASCADE;


--
-- Name: homework_task fk_homework_task__homework; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.homework_task
    ADD CONSTRAINT fk_homework_task__homework FOREIGN KEY (homework_id) REFERENCES core.homework(id) ON DELETE CASCADE;


--
-- Name: homework_task fk_homework_task__task; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.homework_task
    ADD CONSTRAINT fk_homework_task__task FOREIGN KEY (task_id) REFERENCES core.task(id) ON DELETE CASCADE;


--
-- Name: image fk_image__exercise; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.image
    ADD CONSTRAINT fk_image__exercise FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE;


--
-- Name: image fk_image__source_image; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.image
    ADD CONSTRAINT fk_image__source_image FOREIGN KEY (source_image_id) REFERENCES core.image(id) ON DELETE CASCADE;


--
-- Name: image fk_image__task; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.image
    ADD CONSTRAINT fk_image__task FOREIGN KEY (task_id) REFERENCES core.task(id) ON DELETE CASCADE;


--
-- Name: invitation fk_invitation__study_group; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.invitation
    ADD CONSTRAINT fk_invitation__study_group FOREIGN KEY (study_group_id) REFERENCES core.study_group(id) ON DELETE CASCADE;


--
-- Name: learning_link fk_learning_link__course; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.learning_link
    ADD CONSTRAINT fk_learning_link__course FOREIGN KEY (course_id) REFERENCES core.course(id) ON DELETE CASCADE;


--
-- Name: learning_link fk_learning_link__learner_user; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.learning_link
    ADD CONSTRAINT fk_learning_link__learner_user FOREIGN KEY (learner_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE;


--
-- Name: learning_link fk_learning_link__study_language; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.learning_link
    ADD CONSTRAINT fk_learning_link__study_language FOREIGN KEY (study_language_id) REFERENCES core.language(id) ON DELETE RESTRICT;


--
-- Name: learning_link fk_learning_link__target_cefr_level; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.learning_link
    ADD CONSTRAINT fk_learning_link__target_cefr_level FOREIGN KEY (target_cefr_level_id) REFERENCES core.cefr_level(id) ON DELETE RESTRICT;


--
-- Name: learning_link fk_learning_link__teacher_user; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.learning_link
    ADD CONSTRAINT fk_learning_link__teacher_user FOREIGN KEY (teacher_user_id) REFERENCES core.app_user(id) ON DELETE SET NULL;


--
-- Name: learning_link_pseudonym fk_learning_link_pseudonym__learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.learning_link_pseudonym
    ADD CONSTRAINT fk_learning_link_pseudonym__learning_link FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE;


--
-- Name: lesson fk_lesson__learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.lesson
    ADD CONSTRAINT fk_lesson__learning_link FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE;


--
-- Name: lesson fk_lesson__study_group; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.lesson
    ADD CONSTRAINT fk_lesson__study_group FOREIGN KEY (study_group_id) REFERENCES core.study_group(id) ON DELETE CASCADE;


--
-- Name: lesson_exercise fk_lesson_exercise__exercise; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.lesson_exercise
    ADD CONSTRAINT fk_lesson_exercise__exercise FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE;


--
-- Name: lesson_exercise fk_lesson_exercise__lesson; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.lesson_exercise
    ADD CONSTRAINT fk_lesson_exercise__lesson FOREIGN KEY (lesson_id) REFERENCES core.lesson(id) ON DELETE CASCADE;


--
-- Name: lesson_exercise fk_lesson_exercise__shown_to_learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.lesson_exercise
    ADD CONSTRAINT fk_lesson_exercise__shown_to_learning_link FOREIGN KEY (shown_to_learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE;


--
-- Name: level_change fk_level_change__new_cefr_level; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.level_change
    ADD CONSTRAINT fk_level_change__new_cefr_level FOREIGN KEY (new_cefr_level_id) REFERENCES core.cefr_level(id) ON DELETE RESTRICT;


--
-- Name: level_change fk_level_change__previous_cefr_level; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.level_change
    ADD CONSTRAINT fk_level_change__previous_cefr_level FOREIGN KEY (previous_cefr_level_id) REFERENCES core.cefr_level(id) ON DELETE RESTRICT;


--
-- Name: level_change fk_level_change__scale_level; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.level_change
    ADD CONSTRAINT fk_level_change__scale_level FOREIGN KEY (scale_level_id) REFERENCES core.scale_level(id) ON DELETE CASCADE;


--
-- Name: material fk_material__cefr_level; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.material
    ADD CONSTRAINT fk_material__cefr_level FOREIGN KEY (cefr_level_id) REFERENCES core.cefr_level(id) ON DELETE RESTRICT;


--
-- Name: material fk_material__course; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.material
    ADD CONSTRAINT fk_material__course FOREIGN KEY (course_id) REFERENCES core.course(id) ON DELETE SET NULL;


--
-- Name: material fk_material__folder; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.material
    ADD CONSTRAINT fk_material__folder FOREIGN KEY (folder_id) REFERENCES core.folder(id) ON DELETE RESTRICT;


--
-- Name: material fk_material__owner_user; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.material
    ADD CONSTRAINT fk_material__owner_user FOREIGN KEY (owner_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE;


--
-- Name: material fk_material__study_language; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.material
    ADD CONSTRAINT fk_material__study_language FOREIGN KEY (study_language_id) REFERENCES core.language(id) ON DELETE RESTRICT;


--
-- Name: note fk_note__learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.note
    ADD CONSTRAINT fk_note__learning_link FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE;


--
-- Name: note fk_note__lesson; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.note
    ADD CONSTRAINT fk_note__lesson FOREIGN KEY (lesson_id) REFERENCES core.lesson(id) ON DELETE SET NULL;


--
-- Name: oral_error fk_oral_error__error_type; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.oral_error
    ADD CONSTRAINT fk_oral_error__error_type FOREIGN KEY (error_type_id) REFERENCES core.error_type(id) ON DELETE RESTRICT;


--
-- Name: oral_error fk_oral_error__learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.oral_error
    ADD CONSTRAINT fk_oral_error__learning_link FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE;


--
-- Name: oral_error fk_oral_error__lesson; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.oral_error
    ADD CONSTRAINT fk_oral_error__lesson FOREIGN KEY (lesson_id) REFERENCES core.lesson(id) ON DELETE SET NULL;


--
-- Name: oral_error fk_oral_error__scale; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.oral_error
    ADD CONSTRAINT fk_oral_error__scale FOREIGN KEY (scale_id) REFERENCES core.scale(id) ON DELETE RESTRICT;


--
-- Name: oral_error fk_oral_error__task; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.oral_error
    ADD CONSTRAINT fk_oral_error__task FOREIGN KEY (task_id) REFERENCES core.task(id) ON DELETE SET NULL;


--
-- Name: oral_error fk_oral_error__topic; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.oral_error
    ADD CONSTRAINT fk_oral_error__topic FOREIGN KEY (topic_id) REFERENCES core.topic(id) ON DELETE SET NULL;


--
-- Name: parsing_run fk_parsing_run__material; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.parsing_run
    ADD CONSTRAINT fk_parsing_run__material FOREIGN KEY (material_id) REFERENCES core.material(id) ON DELETE CASCADE;


--
-- Name: presentation_item fk_presentation_item__exercise; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.presentation_item
    ADD CONSTRAINT fk_presentation_item__exercise FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE;


--
-- Name: presentation_item fk_presentation_item__task; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.presentation_item
    ADD CONSTRAINT fk_presentation_item__task FOREIGN KEY (task_id) REFERENCES core.task(id) ON DELETE CASCADE;


--
-- Name: pronunciation_choice fk_pronunciation_choice__learner_user; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pronunciation_choice
    ADD CONSTRAINT fk_pronunciation_choice__learner_user FOREIGN KEY (learner_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE;


--
-- Name: pronunciation_choice fk_pronunciation_choice__variant; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pronunciation_choice
    ADD CONSTRAINT fk_pronunciation_choice__variant FOREIGN KEY (pronunciation_variant_id, language_id) REFERENCES core.pronunciation_variant(id, language_id) ON DELETE RESTRICT;


--
-- Name: pronunciation_variant fk_pronunciation_variant__language; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.pronunciation_variant
    ADD CONSTRAINT fk_pronunciation_variant__language FOREIGN KEY (language_id) REFERENCES core.language(id) ON DELETE RESTRICT;


--
-- Name: revision_record fk_revision_record__learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.revision_record
    ADD CONSTRAINT fk_revision_record__learning_link FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE;


--
-- Name: revision_record fk_revision_record__task; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.revision_record
    ADD CONSTRAINT fk_revision_record__task FOREIGN KEY (task_id) REFERENCES core.task(id) ON DELETE CASCADE;


--
-- Name: scale_level fk_scale_level__current_cefr_level; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.scale_level
    ADD CONSTRAINT fk_scale_level__current_cefr_level FOREIGN KEY (current_cefr_level_id) REFERENCES core.cefr_level(id) ON DELETE RESTRICT;


--
-- Name: scale_level fk_scale_level__entry_cefr_level; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.scale_level
    ADD CONSTRAINT fk_scale_level__entry_cefr_level FOREIGN KEY (entry_cefr_level_id) REFERENCES core.cefr_level(id) ON DELETE RESTRICT;


--
-- Name: scale_level fk_scale_level__learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.scale_level
    ADD CONSTRAINT fk_scale_level__learning_link FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE;


--
-- Name: scale_level fk_scale_level__scale; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.scale_level
    ADD CONSTRAINT fk_scale_level__scale FOREIGN KEY (scale_id) REFERENCES core.scale(id) ON DELETE RESTRICT;


--
-- Name: shown_tooltip fk_shown_tooltip__app_user; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.shown_tooltip
    ADD CONSTRAINT fk_shown_tooltip__app_user FOREIGN KEY (app_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE;


--
-- Name: study_group fk_study_group__study_language; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.study_group
    ADD CONSTRAINT fk_study_group__study_language FOREIGN KEY (study_language_id) REFERENCES core.language(id) ON DELETE RESTRICT;


--
-- Name: study_group fk_study_group__teacher_user; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.study_group
    ADD CONSTRAINT fk_study_group__teacher_user FOREIGN KEY (teacher_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE;


--
-- Name: summary_link fk_summary_link__learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.summary_link
    ADD CONSTRAINT fk_summary_link__learning_link FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE;


--
-- Name: task fk_task__exercise; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.task
    ADD CONSTRAINT fk_task__exercise FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE;


--
-- Name: task_target_word fk_task_target_word__task; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.task_target_word
    ADD CONSTRAINT fk_task_target_word__task FOREIGN KEY (task_id) REFERENCES core.task(id) ON DELETE CASCADE;


--
-- Name: task_target_word fk_task_target_word__word; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.task_target_word
    ADD CONSTRAINT fk_task_target_word__word FOREIGN KEY (word_id) REFERENCES core.word(id) ON DELETE RESTRICT;


--
-- Name: topic fk_topic__owner_user; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.topic
    ADD CONSTRAINT fk_topic__owner_user FOREIGN KEY (owner_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE;


--
-- Name: topic_priority fk_topic_priority__learning_link; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.topic_priority
    ADD CONSTRAINT fk_topic_priority__learning_link FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE;


--
-- Name: topic_priority fk_topic_priority__topic; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.topic_priority
    ADD CONSTRAINT fk_topic_priority__topic FOREIGN KEY (topic_id) REFERENCES core.topic(id) ON DELETE CASCADE;


--
-- Name: word fk_word__language; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.word
    ADD CONSTRAINT fk_word__language FOREIGN KEY (language_id) REFERENCES core.language(id) ON DELETE RESTRICT;


--
-- Name: word_pronunciation fk_word_pronunciation__variant; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.word_pronunciation
    ADD CONSTRAINT fk_word_pronunciation__variant FOREIGN KEY (pronunciation_variant_id, language_id) REFERENCES core.pronunciation_variant(id, language_id) ON DELETE RESTRICT;


--
-- Name: word_pronunciation fk_word_pronunciation__word; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.word_pronunciation
    ADD CONSTRAINT fk_word_pronunciation__word FOREIGN KEY (word_id, language_id) REFERENCES core.word(id, language_id) ON DELETE CASCADE;


--
-- Name: statistics_event fk_statistics_event__cefr_level; Type: FK CONSTRAINT; Schema: stats; Owner: -
--

ALTER TABLE ONLY stats.statistics_event
    ADD CONSTRAINT fk_statistics_event__cefr_level FOREIGN KEY (cefr_level_id) REFERENCES core.cefr_level(id) ON DELETE RESTRICT;


--
-- Name: statistics_event fk_statistics_event__exercise_type; Type: FK CONSTRAINT; Schema: stats; Owner: -
--

ALTER TABLE ONLY stats.statistics_event
    ADD CONSTRAINT fk_statistics_event__exercise_type FOREIGN KEY (exercise_type_id) REFERENCES core.exercise_type(id) ON DELETE RESTRICT;


--
-- Name: statistics_event fk_statistics_event__scale; Type: FK CONSTRAINT; Schema: stats; Owner: -
--

ALTER TABLE ONLY stats.statistics_event
    ADD CONSTRAINT fk_statistics_event__scale FOREIGN KEY (scale_id) REFERENCES core.scale(id) ON DELETE RESTRICT;


--
-- Name: statistics_event fk_statistics_event__topic; Type: FK CONSTRAINT; Schema: stats; Owner: -
--

ALTER TABLE ONLY stats.statistics_event
    ADD CONSTRAINT fk_statistics_event__topic FOREIGN KEY (topic_id) REFERENCES core.topic(id) ON DELETE RESTRICT;


--
-- Name: SCHEMA core; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA core TO ilp_read;
GRANT USAGE ON SCHEMA core TO ilp_write;
GRANT ALL ON SCHEMA core TO ilp_admin;


--
-- Name: SCHEMA stats; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA stats TO ilp_read;
GRANT USAGE ON SCHEMA stats TO ilp_write;
GRANT ALL ON SCHEMA stats TO ilp_admin;


--
-- Name: PROCEDURE erase_personal_data(IN p_erasure_request_id bigint); Type: ACL; Schema: core; Owner: -
--

REVOKE ALL ON PROCEDURE core.erase_personal_data(IN p_erasure_request_id bigint) FROM PUBLIC;
GRANT ALL ON PROCEDURE core.erase_personal_data(IN p_erasure_request_id bigint) TO ilp_write;
GRANT ALL ON PROCEDURE core.erase_personal_data(IN p_erasure_request_id bigint) TO ilp_admin;


--
-- Name: PROCEDURE purge_retained_materials(); Type: ACL; Schema: core; Owner: -
--

REVOKE ALL ON PROCEDURE core.purge_retained_materials() FROM PUBLIC;
GRANT ALL ON PROCEDURE core.purge_retained_materials() TO ilp_write;
GRANT ALL ON PROCEDURE core.purge_retained_materials() TO ilp_admin;


--
-- Name: PROCEDURE refresh_statistics_summary(); Type: ACL; Schema: stats; Owner: -
--

REVOKE ALL ON PROCEDURE stats.refresh_statistics_summary() FROM PUBLIC;
GRANT ALL ON PROCEDURE stats.refresh_statistics_summary() TO ilp_write;
GRANT ALL ON PROCEDURE stats.refresh_statistics_summary() TO ilp_admin;


--
-- Name: TABLE adaptation_proposal; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.adaptation_proposal TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.adaptation_proposal TO ilp_write;
GRANT ALL ON TABLE core.adaptation_proposal TO ilp_admin;


--
-- Name: TABLE adaptation_proposal_item; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.adaptation_proposal_item TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.adaptation_proposal_item TO ilp_write;
GRANT ALL ON TABLE core.adaptation_proposal_item TO ilp_admin;


--
-- Name: TABLE answer; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.answer TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.answer TO ilp_write;
GRANT ALL ON TABLE core.answer TO ilp_admin;


--
-- Name: TABLE app_user; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.app_user TO ilp_write;
GRANT ALL ON TABLE core.app_user TO ilp_admin;


--
-- Name: COLUMN app_user.id; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(id) ON TABLE core.app_user TO ilp_read;


--
-- Name: COLUMN app_user.country_id; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(country_id) ON TABLE core.app_user TO ilp_read;


--
-- Name: COLUMN app_user.age_group; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(age_group) ON TABLE core.app_user TO ilp_read;


--
-- Name: COLUMN app_user.registration_role; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(registration_role) ON TABLE core.app_user TO ilp_read;


--
-- Name: COLUMN app_user.interface_language_id; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(interface_language_id) ON TABLE core.app_user TO ilp_read;


--
-- Name: COLUMN app_user.registered_at; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(registered_at) ON TABLE core.app_user TO ilp_read;


--
-- Name: COLUMN app_user.time_zone; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(time_zone) ON TABLE core.app_user TO ilp_read;


--
-- Name: COLUMN app_user.daily_task_limit; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(daily_task_limit) ON TABLE core.app_user TO ilp_read;


--
-- Name: COLUMN app_user.reminder_time; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(reminder_time) ON TABLE core.app_user TO ilp_read;


--
-- Name: COLUMN app_user.reminders_enabled; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(reminders_enabled) ON TABLE core.app_user TO ilp_read;


--
-- Name: COLUMN app_user.last_reminder_sent_at; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(last_reminder_sent_at) ON TABLE core.app_user TO ilp_read;


--
-- Name: COLUMN app_user.visual_style_id; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(visual_style_id) ON TABLE core.app_user TO ilp_read;


--
-- Name: COLUMN app_user.show_added_glossaries; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(show_added_glossaries) ON TABLE core.app_user TO ilp_read;


--
-- Name: TABLE cefr_level; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.cefr_level TO ilp_read;
GRANT SELECT ON TABLE core.cefr_level TO ilp_write;
GRANT ALL ON TABLE core.cefr_level TO ilp_admin;


--
-- Name: TABLE competition; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.competition TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.competition TO ilp_write;
GRANT ALL ON TABLE core.competition TO ilp_admin;


--
-- Name: TABLE competition_participation; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.competition_participation TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.competition_participation TO ilp_write;
GRANT ALL ON TABLE core.competition_participation TO ilp_admin;


--
-- Name: TABLE consent; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.consent TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.consent TO ilp_write;
GRANT ALL ON TABLE core.consent TO ilp_admin;


--
-- Name: TABLE country; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.country TO ilp_read;
GRANT SELECT ON TABLE core.country TO ilp_write;
GRANT ALL ON TABLE core.country TO ilp_admin;


--
-- Name: TABLE course; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.course TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.course TO ilp_write;
GRANT ALL ON TABLE core.course TO ilp_admin;


--
-- Name: TABLE erasure_request; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.erasure_request TO ilp_write;
GRANT ALL ON TABLE core.erasure_request TO ilp_admin;


--
-- Name: COLUMN erasure_request.id; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(id) ON TABLE core.erasure_request TO ilp_read;


--
-- Name: COLUMN erasure_request.app_user_id; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(app_user_id) ON TABLE core.erasure_request TO ilp_read;


--
-- Name: COLUMN erasure_request.learning_link_id; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(learning_link_id) ON TABLE core.erasure_request TO ilp_read;


--
-- Name: COLUMN erasure_request.requested_at; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(requested_at) ON TABLE core.erasure_request TO ilp_read;


--
-- Name: COLUMN erasure_request.confirm_by; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(confirm_by) ON TABLE core.erasure_request TO ilp_read;


--
-- Name: COLUMN erasure_request.confirmed_at; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(confirmed_at) ON TABLE core.erasure_request TO ilp_read;


--
-- Name: COLUMN erasure_request.execute_by; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(execute_by) ON TABLE core.erasure_request TO ilp_read;


--
-- Name: COLUMN erasure_request.status; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(status) ON TABLE core.erasure_request TO ilp_read;


--
-- Name: COLUMN erasure_request.scope; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(scope) ON TABLE core.erasure_request TO ilp_read;


--
-- Name: COLUMN erasure_request.material_retention_days; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(material_retention_days) ON TABLE core.erasure_request TO ilp_read;


--
-- Name: TABLE error_type; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.error_type TO ilp_read;
GRANT SELECT ON TABLE core.error_type TO ilp_write;
GRANT ALL ON TABLE core.error_type TO ilp_admin;


--
-- Name: TABLE exercise; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.exercise TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.exercise TO ilp_write;
GRANT ALL ON TABLE core.exercise TO ilp_admin;


--
-- Name: TABLE exercise_dependency; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.exercise_dependency TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.exercise_dependency TO ilp_write;
GRANT ALL ON TABLE core.exercise_dependency TO ilp_admin;


--
-- Name: TABLE exercise_target_word; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.exercise_target_word TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.exercise_target_word TO ilp_write;
GRANT ALL ON TABLE core.exercise_target_word TO ilp_admin;


--
-- Name: TABLE exercise_type; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.exercise_type TO ilp_read;
GRANT SELECT ON TABLE core.exercise_type TO ilp_write;
GRANT ALL ON TABLE core.exercise_type TO ilp_admin;


--
-- Name: TABLE exercise_type_compatibility; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.exercise_type_compatibility TO ilp_read;
GRANT SELECT ON TABLE core.exercise_type_compatibility TO ilp_write;
GRANT ALL ON TABLE core.exercise_type_compatibility TO ilp_admin;


--
-- Name: TABLE export_request; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.export_request TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.export_request TO ilp_write;
GRANT ALL ON TABLE core.export_request TO ilp_admin;


--
-- Name: TABLE feature_toggle; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.feature_toggle TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.feature_toggle TO ilp_write;
GRANT ALL ON TABLE core.feature_toggle TO ilp_admin;


--
-- Name: TABLE flag; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.flag TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.flag TO ilp_write;
GRANT ALL ON TABLE core.flag TO ilp_admin;


--
-- Name: TABLE flag_reason; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.flag_reason TO ilp_read;
GRANT SELECT ON TABLE core.flag_reason TO ilp_write;
GRANT ALL ON TABLE core.flag_reason TO ilp_admin;


--
-- Name: TABLE folder; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.folder TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.folder TO ilp_write;
GRANT ALL ON TABLE core.folder TO ilp_admin;


--
-- Name: TABLE group_membership; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.group_membership TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.group_membership TO ilp_write;
GRANT ALL ON TABLE core.group_membership TO ilp_admin;


--
-- Name: TABLE homework; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.homework TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.homework TO ilp_write;
GRANT ALL ON TABLE core.homework TO ilp_admin;


--
-- Name: TABLE homework_assignment; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.homework_assignment TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.homework_assignment TO ilp_write;
GRANT ALL ON TABLE core.homework_assignment TO ilp_admin;


--
-- Name: TABLE homework_exercise; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.homework_exercise TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.homework_exercise TO ilp_write;
GRANT ALL ON TABLE core.homework_exercise TO ilp_admin;


--
-- Name: TABLE homework_task; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.homework_task TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.homework_task TO ilp_write;
GRANT ALL ON TABLE core.homework_task TO ilp_admin;


--
-- Name: TABLE image; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.image TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.image TO ilp_write;
GRANT ALL ON TABLE core.image TO ilp_admin;


--
-- Name: TABLE invitation; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.invitation TO ilp_write;
GRANT ALL ON TABLE core.invitation TO ilp_admin;


--
-- Name: COLUMN invitation.id; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(id) ON TABLE core.invitation TO ilp_read;


--
-- Name: COLUMN invitation.study_group_id; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(study_group_id) ON TABLE core.invitation TO ilp_read;


--
-- Name: COLUMN invitation.valid_until; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(valid_until) ON TABLE core.invitation TO ilp_read;


--
-- Name: COLUMN invitation.revoked_at; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(revoked_at) ON TABLE core.invitation TO ilp_read;


--
-- Name: TABLE language; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.language TO ilp_read;
GRANT SELECT ON TABLE core.language TO ilp_write;
GRANT ALL ON TABLE core.language TO ilp_admin;


--
-- Name: TABLE learning_link; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.learning_link TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.learning_link TO ilp_write;
GRANT ALL ON TABLE core.learning_link TO ilp_admin;


--
-- Name: TABLE learning_link_pseudonym; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.learning_link_pseudonym TO ilp_write;
GRANT ALL ON TABLE core.learning_link_pseudonym TO ilp_admin;


--
-- Name: TABLE lesson; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.lesson TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.lesson TO ilp_write;
GRANT ALL ON TABLE core.lesson TO ilp_admin;


--
-- Name: TABLE lesson_exercise; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.lesson_exercise TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.lesson_exercise TO ilp_write;
GRANT ALL ON TABLE core.lesson_exercise TO ilp_admin;


--
-- Name: TABLE level_change; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.level_change TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.level_change TO ilp_write;
GRANT ALL ON TABLE core.level_change TO ilp_admin;


--
-- Name: TABLE material; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.material TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.material TO ilp_write;
GRANT ALL ON TABLE core.material TO ilp_admin;


--
-- Name: TABLE note; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.note TO ilp_write;
GRANT ALL ON TABLE core.note TO ilp_admin;


--
-- Name: COLUMN note.id; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(id) ON TABLE core.note TO ilp_read;


--
-- Name: COLUMN note.learning_link_id; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(learning_link_id) ON TABLE core.note TO ilp_read;


--
-- Name: COLUMN note.lesson_id; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(lesson_id) ON TABLE core.note TO ilp_read;


--
-- Name: COLUMN note.written_at; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(written_at) ON TABLE core.note TO ilp_read;


--
-- Name: TABLE oral_error; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.oral_error TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.oral_error TO ilp_write;
GRANT ALL ON TABLE core.oral_error TO ilp_admin;


--
-- Name: TABLE parsing_run; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.parsing_run TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.parsing_run TO ilp_write;
GRANT ALL ON TABLE core.parsing_run TO ilp_admin;


--
-- Name: TABLE policy_version; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.policy_version TO ilp_read;
GRANT SELECT ON TABLE core.policy_version TO ilp_write;
GRANT ALL ON TABLE core.policy_version TO ilp_admin;


--
-- Name: TABLE presentation_item; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.presentation_item TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.presentation_item TO ilp_write;
GRANT ALL ON TABLE core.presentation_item TO ilp_admin;


--
-- Name: TABLE pronunciation_choice; Type: ACL; Schema: core; Owner: -
--

GRANT ALL ON TABLE core.pronunciation_choice TO ilp_admin;
GRANT SELECT ON TABLE core.pronunciation_choice TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.pronunciation_choice TO ilp_write;


--
-- Name: TABLE pronunciation_variant; Type: ACL; Schema: core; Owner: -
--

GRANT ALL ON TABLE core.pronunciation_variant TO ilp_admin;
GRANT SELECT ON TABLE core.pronunciation_variant TO ilp_read;
GRANT SELECT ON TABLE core.pronunciation_variant TO ilp_write;


--
-- Name: TABLE revision_record; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.revision_record TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.revision_record TO ilp_write;
GRANT ALL ON TABLE core.revision_record TO ilp_admin;


--
-- Name: TABLE scale; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.scale TO ilp_read;
GRANT SELECT ON TABLE core.scale TO ilp_write;
GRANT ALL ON TABLE core.scale TO ilp_admin;


--
-- Name: TABLE scale_level; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.scale_level TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.scale_level TO ilp_write;
GRANT ALL ON TABLE core.scale_level TO ilp_admin;


--
-- Name: TABLE shown_tooltip; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.shown_tooltip TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.shown_tooltip TO ilp_write;
GRANT ALL ON TABLE core.shown_tooltip TO ilp_admin;


--
-- Name: TABLE study_group; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.study_group TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.study_group TO ilp_write;
GRANT ALL ON TABLE core.study_group TO ilp_admin;


--
-- Name: TABLE summary_link; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.summary_link TO ilp_write;
GRANT ALL ON TABLE core.summary_link TO ilp_admin;


--
-- Name: COLUMN summary_link.id; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(id) ON TABLE core.summary_link TO ilp_read;


--
-- Name: COLUMN summary_link.learning_link_id; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(learning_link_id) ON TABLE core.summary_link TO ilp_read;


--
-- Name: COLUMN summary_link.created_at; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(created_at) ON TABLE core.summary_link TO ilp_read;


--
-- Name: COLUMN summary_link.valid_until; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(valid_until) ON TABLE core.summary_link TO ilp_read;


--
-- Name: COLUMN summary_link.revoked_at; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT(revoked_at) ON TABLE core.summary_link TO ilp_read;


--
-- Name: TABLE task; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.task TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.task TO ilp_write;
GRANT ALL ON TABLE core.task TO ilp_admin;


--
-- Name: TABLE task_target_word; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.task_target_word TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.task_target_word TO ilp_write;
GRANT ALL ON TABLE core.task_target_word TO ilp_admin;


--
-- Name: TABLE topic; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.topic TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.topic TO ilp_write;
GRANT ALL ON TABLE core.topic TO ilp_admin;


--
-- Name: TABLE topic_priority; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.topic_priority TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.topic_priority TO ilp_write;
GRANT ALL ON TABLE core.topic_priority TO ilp_admin;


--
-- Name: TABLE v_app_user_masked; Type: ACL; Schema: core; Owner: -
--

GRANT ALL ON TABLE core.v_app_user_masked TO ilp_admin;
GRANT SELECT ON TABLE core.v_app_user_masked TO ilp_read;


--
-- Name: TABLE v_material_expiring; Type: ACL; Schema: core; Owner: -
--

GRANT ALL ON TABLE core.v_material_expiring TO ilp_admin;
GRANT SELECT ON TABLE core.v_material_expiring TO ilp_read;
GRANT SELECT ON TABLE core.v_material_expiring TO ilp_write;


--
-- Name: TABLE v_note_masked; Type: ACL; Schema: core; Owner: -
--

GRANT ALL ON TABLE core.v_note_masked TO ilp_admin;
GRANT SELECT ON TABLE core.v_note_masked TO ilp_read;


--
-- Name: TABLE v_revision_queue; Type: ACL; Schema: core; Owner: -
--

GRANT ALL ON TABLE core.v_revision_queue TO ilp_admin;
GRANT SELECT ON TABLE core.v_revision_queue TO ilp_read;
GRANT SELECT ON TABLE core.v_revision_queue TO ilp_write;


--
-- Name: TABLE visual_style; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.visual_style TO ilp_read;
GRANT SELECT ON TABLE core.visual_style TO ilp_write;
GRANT ALL ON TABLE core.visual_style TO ilp_admin;


--
-- Name: TABLE word; Type: ACL; Schema: core; Owner: -
--

GRANT SELECT ON TABLE core.word TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.word TO ilp_write;
GRANT ALL ON TABLE core.word TO ilp_admin;


--
-- Name: TABLE word_pronunciation; Type: ACL; Schema: core; Owner: -
--

GRANT ALL ON TABLE core.word_pronunciation TO ilp_admin;
GRANT SELECT ON TABLE core.word_pronunciation TO ilp_read;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE core.word_pronunciation TO ilp_write;


--
-- Name: TABLE statistics_event; Type: ACL; Schema: stats; Owner: -
--

GRANT SELECT ON TABLE stats.statistics_event TO ilp_read;
GRANT SELECT,INSERT ON TABLE stats.statistics_event TO ilp_write;
GRANT ALL ON TABLE stats.statistics_event TO ilp_admin;


--
-- Name: TABLE mv_statistics_summary; Type: ACL; Schema: stats; Owner: -
--

GRANT ALL ON TABLE stats.mv_statistics_summary TO ilp_admin;
GRANT SELECT ON TABLE stats.mv_statistics_summary TO ilp_read;
GRANT SELECT ON TABLE stats.mv_statistics_summary TO ilp_write;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: core; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE ilp_owner IN SCHEMA core GRANT ALL ON TABLES TO ilp_admin;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: stats; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE ilp_owner IN SCHEMA stats GRANT ALL ON TABLES TO ilp_admin;


--
-- PostgreSQL database dump complete
--

