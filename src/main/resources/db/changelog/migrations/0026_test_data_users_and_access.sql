--liquibase formatted sql

--changeset samitava:0026-test-users-and-access context:test splitStatements:false
DO $$
DECLARE
    v_lt       bigint := (SELECT id FROM core.country WHERE code = 'LT');
    v_en       bigint := (SELECT id FROM core.language WHERE code = 'en');
    v_ru       bigint := (SELECT id FROM core.language WHERE code = 'ru');
    v_policy   bigint := (SELECT id FROM core.policy_version WHERE version_number = '1.0');
    v_style    bigint := (SELECT id FROM core.visual_style WHERE code = 'default');
    v_b2       bigint := (SELECT id FROM core.cefr_level WHERE name = 'B2');
    v_hash     text := '$argon2id$v=19$m=19456,t=2,p=1$W2CQPCVHMunNXR+YhQyasA$JDdjiumyd8JqOUUaTYtCt6URQDlncQ75bbDkqFd7JdM';
    v_anna     bigint;
    v_eva      bigint;
    v_ben      bigint;
    v_carla    bigint;
    v_dan      bigint;
    v_group    bigint;
    v_course_ben bigint;
    v_course_dan bigint;
    v_course_eva bigint;
    v_link_ben_anna  bigint;
    v_link_carla_anna bigint;
    v_link_carla_eva bigint;
    v_link_ben_self  bigint;
    v_link_dan_self  bigint;
    v_link_eva_self  bigint;
    v_link_ben_eva_ended bigint;
BEGIN
    INSERT INTO core.app_user (email, password_hash, country_id, age_group, registration_role, display_name,
                               interface_language_id, registered_at, time_zone, visual_style_id)
    VALUES ('anna.teacher@example.com', v_hash, v_lt, 'adult', 'teacher', 'Anna', v_en,
            TIMESTAMPTZ '2026-09-01 09:00+03', 'Europe/Vilnius', v_style)
    RETURNING id INTO v_anna;

    INSERT INTO core.app_user (email, password_hash, country_id, age_group, registration_role, display_name,
                               interface_language_id, registered_at, time_zone, reminder_time, reminders_enabled)
    VALUES ('eva.teacher@example.com', v_hash, v_lt, 'adult', 'teacher', 'Eva', v_ru,
            TIMESTAMPTZ '2026-09-02 10:00+03', 'Europe/Vilnius', TIME '18:00', true)
    RETURNING id INTO v_eva;

    INSERT INTO core.app_user (email, password_hash, country_id, age_group, registration_role, display_name,
                               interface_language_id, registered_at, time_zone, daily_task_limit)
    VALUES ('ben.learner@example.com', v_hash, v_lt, 'adult', 'learner', 'Ben', v_en,
            TIMESTAMPTZ '2026-09-03 11:00+03', 'Europe/Vilnius', 20)
    RETURNING id INTO v_ben;

    INSERT INTO core.app_user (email, password_hash, country_id, age_group, registration_role, display_name,
                               interface_language_id, registered_at, time_zone)
    VALUES ('carla.learner@example.com', v_hash, v_lt, '14-17', 'learner', NULL, v_ru,
            TIMESTAMPTZ '2026-09-04 12:00+03', 'Europe/Vilnius')
    RETURNING id INTO v_carla;

    INSERT INTO core.app_user (email, password_hash, country_id, age_group, registration_role, display_name,
                               interface_language_id, registered_at, time_zone, show_added_glossaries)
    VALUES ('dan.learner@example.com', v_hash, v_lt, 'adult', 'learner', 'Dan', v_en,
            TIMESTAMPTZ '2026-09-05 13:00+03', 'Europe/Vilnius', false)
    RETURNING id INTO v_dan;

    INSERT INTO core.consent (app_user_id, consent_kind, given_at, policy_version_id, withdrawn_at) VALUES
        (v_anna,  'main',       TIMESTAMPTZ '2026-09-01 09:00+03', v_policy, NULL),
        (v_anna,  'statistics', TIMESTAMPTZ '2026-09-01 09:00+03', v_policy, NULL),
        (v_eva,   'main',       TIMESTAMPTZ '2026-09-02 10:00+03', v_policy, NULL),
        (v_eva,   'statistics', TIMESTAMPTZ '2026-09-02 10:00+03', v_policy, NULL),
        (v_ben,   'main',       TIMESTAMPTZ '2026-09-03 11:00+03', v_policy, NULL),
        (v_ben,   'statistics', TIMESTAMPTZ '2026-09-03 11:00+03', v_policy, NULL),
        (v_carla, 'main',       TIMESTAMPTZ '2026-09-04 12:00+03', v_policy, NULL),
        (v_dan,   'main',       TIMESTAMPTZ '2026-09-05 13:00+03', v_policy, NULL),
        (v_dan,   'statistics', TIMESTAMPTZ '2026-09-05 13:00+03', v_policy, TIMESTAMPTZ '2026-10-01 08:00+03');

    INSERT INTO core.study_group (name, teacher_user_id, created_at, study_language_id)
    VALUES ('Tuesday evening group', v_anna, TIMESTAMPTZ '2026-09-06 09:00+03', v_en)
    RETURNING id INTO v_group;

    INSERT INTO core.invitation (study_group_id, code, valid_until, revoked_at) VALUES
        (v_group, 'TEST-INVITE-ACTIVE',  TIMESTAMPTZ '2026-12-31 23:59+02', NULL),
        (v_group, 'TEST-INVITE-REVOKED', TIMESTAMPTZ '2026-12-31 23:59+02', TIMESTAMPTZ '2026-09-10 09:00+03');

    INSERT INTO core.course (name, owner_user_id, created_at)
    VALUES ('English vocabulary on my own', v_ben, TIMESTAMPTZ '2026-09-07 09:00+03')
    RETURNING id INTO v_course_ben;
    INSERT INTO core.course (name, owner_user_id, created_at)
    VALUES ('English for travel', v_dan, TIMESTAMPTZ '2026-09-07 10:00+03')
    RETURNING id INTO v_course_dan;
    INSERT INTO core.course (name, owner_user_id, created_at)
    VALUES ('Russian for myself', v_eva, TIMESTAMPTZ '2026-09-07 11:00+03')
    RETURNING id INTO v_course_eva;

    INSERT INTO core.learning_link (link_kind, learner_user_id, teacher_user_id, course_id, goal, target_cefr_level_id,
                                    started_at, ended_at, study_language_id, level_decision_mode,
                                    adaptation_decision_mode, queue_decision_mode, total_course_hours, desired_end_date)
    VALUES ('with_teacher', v_ben, v_anna, NULL, 'Pass a B2 exam', v_b2,
            TIMESTAMPTZ '2026-09-08 09:00+03', NULL, v_en, 'self', 'self', 'system', 180, DATE '2027-06-30')
    RETURNING id INTO v_link_ben_anna;

    INSERT INTO core.learning_link (link_kind, learner_user_id, teacher_user_id, started_at, study_language_id,
                                    level_decision_mode, adaptation_decision_mode, queue_decision_mode)
    VALUES ('with_teacher', v_carla, v_anna, TIMESTAMPTZ '2026-09-08 10:00+03', v_en, 'self', 'self', 'self')
    RETURNING id INTO v_link_carla_anna;

    INSERT INTO core.learning_link (link_kind, learner_user_id, teacher_user_id, started_at, study_language_id,
                                    level_decision_mode, adaptation_decision_mode, queue_decision_mode)
    VALUES ('with_teacher', v_carla, v_eva, TIMESTAMPTZ '2026-09-09 10:00+03', v_en, 'self', 'self', 'self')
    RETURNING id INTO v_link_carla_eva;

    INSERT INTO core.learning_link (link_kind, learner_user_id, teacher_user_id, started_at, ended_at, study_language_id,
                                    level_decision_mode, adaptation_decision_mode, queue_decision_mode)
    VALUES ('with_teacher', v_ben, v_eva, TIMESTAMPTZ '2026-06-01 10:00+03', TIMESTAMPTZ '2026-08-31 10:00+03', v_en,
            'self', 'self', 'self')
    RETURNING id INTO v_link_ben_eva_ended;

    INSERT INTO core.learning_link (link_kind, learner_user_id, course_id, started_at, study_language_id,
                                    level_decision_mode, adaptation_decision_mode, queue_decision_mode,
                                    new_material_share, failures_before_deferral)
    VALUES ('self_directed', v_ben, v_course_ben, TIMESTAMPTZ '2026-09-07 09:00+03', v_en,
            'system', 'system', 'system', 0.20, 8)
    RETURNING id INTO v_link_ben_self;

    INSERT INTO core.learning_link (link_kind, learner_user_id, course_id, started_at, study_language_id,
                                    level_decision_mode, adaptation_decision_mode, queue_decision_mode)
    VALUES ('self_directed', v_dan, v_course_dan, TIMESTAMPTZ '2026-09-07 10:00+03', v_en, 'system', 'self', 'system')
    RETURNING id INTO v_link_dan_self;

    INSERT INTO core.learning_link (link_kind, learner_user_id, course_id, started_at, study_language_id,
                                    level_decision_mode, adaptation_decision_mode, queue_decision_mode)
    VALUES ('self_directed', v_eva, v_course_eva, TIMESTAMPTZ '2026-09-07 11:00+03', v_ru, 'self', 'self', 'self')
    RETURNING id INTO v_link_eva_self;

    INSERT INTO core.group_membership (learning_link_id, study_group_id, joined_at, left_at) VALUES
        (v_link_ben_anna,   v_group, TIMESTAMPTZ '2026-09-08 09:00+03', NULL),
        (v_link_carla_anna, v_group, TIMESTAMPTZ '2026-09-08 10:00+03', TIMESTAMPTZ '2026-09-20 10:00+03'),
        (v_link_carla_anna, v_group, TIMESTAMPTZ '2026-09-27 10:00+03', NULL);

    INSERT INTO core.feature_toggle (feature, study_group_id, learning_link_id, is_enabled, changed_at) VALUES
        ('harder_variants',  v_group, NULL,              false, TIMESTAMPTZ '2026-09-10 09:00+03'),
        ('oral_error_entry', NULL,    v_link_ben_anna,   true,  TIMESTAMPTZ '2026-09-10 09:05+03'),
        ('adaptation',       NULL,    v_link_carla_anna, false, TIMESTAMPTZ '2026-09-10 09:10+03');

    INSERT INTO core.shown_tooltip (app_user_id, interface_element, shown_at) VALUES
        (v_ben,   'level_chart',  TIMESTAMPTZ '2026-09-08 09:30+03'),
        (v_carla, 'daily_queue',  TIMESTAMPTZ '2026-09-08 10:30+03');

    INSERT INTO core.summary_link (learning_link_id, code, created_at, valid_until, revoked_at) VALUES
        (v_link_ben_anna, 'TEST-SUMMARY-ACTIVE',  TIMESTAMPTZ '2026-11-10 09:00+02', TIMESTAMPTZ '2026-11-24 09:00+02', NULL),
        (v_link_ben_anna, 'TEST-SUMMARY-REVOKED', TIMESTAMPTZ '2026-10-01 09:00+03', TIMESTAMPTZ '2026-10-15 09:00+03',
         TIMESTAMPTZ '2026-10-02 09:00+03');

    INSERT INTO core.export_request (app_user_id, learning_link_id, requested_at, prepare_by, prepared_at,
                                     file_location, available_until) VALUES
        (v_ben, NULL,            TIMESTAMPTZ '2026-10-05 09:00+03', TIMESTAMPTZ '2026-11-05 09:00+02',
         TIMESTAMPTZ '2026-10-05 09:10+03', 'exports/test/ben-everything.zip', TIMESTAMPTZ '2026-10-12 09:10+03'),
        (v_dan, v_link_dan_self, TIMESTAMPTZ '2026-11-14 09:00+02', TIMESTAMPTZ '2026-12-14 09:00+02', NULL, NULL, NULL);

    INSERT INTO core.erasure_request (app_user_id, learning_link_id, requested_at, confirm_by, confirmed_at,
                                      execute_by, status, scope, confirmation_code_hash) VALUES
        (v_dan, NULL, TIMESTAMPTZ '2026-11-15 09:00+02', TIMESTAMPTZ '2026-11-16 09:00+02', NULL, NULL,
         'awaiting_confirmation', 'everything', v_hash),
        (v_ben, v_link_ben_eva_ended, TIMESTAMPTZ '2026-09-01 09:00+03', TIMESTAMPTZ '2026-09-02 09:00+03',
         TIMESTAMPTZ '2026-09-01 09:20+03', TIMESTAMPTZ '2026-10-01 09:20+03', 'cancelled', 'single_link', NULL);

    INSERT INTO core.learning_link_pseudonym (learning_link_id, created_at) VALUES
        (v_link_ben_anna, TIMESTAMPTZ '2026-09-08 09:00+03'),
        (v_link_ben_self, TIMESTAMPTZ '2026-09-07 09:00+03');
END
$$;
--rollback DELETE FROM core.erasure_request WHERE app_user_id IN (SELECT id FROM core.app_user WHERE email IN ('ben.learner@example.com', 'dan.learner@example.com'));
--rollback DELETE FROM core.app_user WHERE email IN ('ben.learner@example.com', 'carla.learner@example.com', 'dan.learner@example.com');
--rollback DELETE FROM core.app_user WHERE email IN ('anna.teacher@example.com', 'eva.teacher@example.com');
