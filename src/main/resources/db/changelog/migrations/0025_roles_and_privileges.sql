--liquibase formatted sql

--changeset samitava:0025-roles splitStatements:false
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ilp_read') THEN
        CREATE ROLE ilp_read NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ilp_write') THEN
        CREATE ROLE ilp_write NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ilp_admin') THEN
        CREATE ROLE ilp_admin NOLOGIN;
    END IF;
END
$$;
--rollback SELECT 1;

--changeset samitava:0025-read-role-privileges
GRANT USAGE ON SCHEMA core, stats TO ilp_read;
GRANT SELECT ON ALL TABLES IN SCHEMA core, stats TO ilp_read;
REVOKE SELECT ON core.learning_link_pseudonym, core.app_user, core.erasure_request, core.invitation, core.summary_link FROM ilp_read;
GRANT SELECT (id, country_id, age_group, registration_role, interface_language_id, registered_at, time_zone, daily_task_limit, reminder_time, reminders_enabled, last_reminder_sent_at, visual_style_id, show_added_glossaries)
    ON core.app_user TO ilp_read;
GRANT SELECT (id, app_user_id, learning_link_id, requested_at, confirm_by, confirmed_at, execute_by, status, scope)
    ON core.erasure_request TO ilp_read;
GRANT SELECT (id, study_group_id, valid_until, revoked_at)
    ON core.invitation TO ilp_read;
GRANT SELECT (id, learning_link_id, created_at, valid_until, revoked_at)
    ON core.summary_link TO ilp_read;
--rollback REVOKE ALL ON ALL TABLES IN SCHEMA core, stats FROM ilp_read;
--rollback REVOKE ALL ON SCHEMA core, stats FROM ilp_read;

--changeset samitava:0025-write-role-privileges
GRANT USAGE ON SCHEMA core, stats TO ilp_write;
GRANT SELECT ON ALL TABLES IN SCHEMA core, stats TO ilp_write;
GRANT INSERT, UPDATE, DELETE ON
    core.adaptation_proposal, core.adaptation_proposal_item, core.answer, core.app_user,
    core.competition, core.competition_participation, core.consent, core.course,
    core.erasure_request, core.exercise, core.exercise_dependency, core.exercise_target_word,
    core.export_request, core.feature_toggle, core.flag, core.folder, core.group_membership,
    core.homework, core.homework_assignment, core.homework_exercise, core.homework_task, core.image,
    core.invitation, core.learning_link, core.learning_link_pseudonym, core.lesson,
    core.lesson_exercise, core.level_change, core.material, core.note, core.oral_error,
    core.parsing_run, core.presentation_item, core.revision_record, core.scale_level,
    core.shown_tooltip, core.study_group, core.summary_link, core.task, core.task_target_word,
    core.topic, core.topic_priority, core.word
    TO ilp_write;
GRANT INSERT ON stats.statistics_event TO ilp_write;
--rollback REVOKE ALL ON ALL TABLES IN SCHEMA core, stats FROM ilp_write;
--rollback REVOKE ALL ON SCHEMA core, stats FROM ilp_write;

--changeset samitava:0025-admin-role-privileges
GRANT ALL ON SCHEMA core, stats TO ilp_admin;
GRANT ALL ON ALL TABLES IN SCHEMA core, stats TO ilp_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA core, stats GRANT ALL ON TABLES TO ilp_admin;
GRANT ilp_admin TO ilp_owner;
--rollback REVOKE ilp_admin FROM ilp_owner;
--rollback ALTER DEFAULT PRIVILEGES IN SCHEMA core, stats REVOKE ALL ON TABLES FROM ilp_admin;
--rollback REVOKE ALL ON ALL TABLES IN SCHEMA core, stats FROM ilp_admin;
--rollback REVOKE ALL ON SCHEMA core, stats FROM ilp_admin;
