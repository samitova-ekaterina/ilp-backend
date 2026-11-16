--liquibase formatted sql

--changeset samitava:0029-test-adaptation-competitions-statistics context:test splitStatements:false
DO $$
DECLARE
    v_anna  bigint := (SELECT id FROM core.app_user WHERE email = 'anna.teacher@example.com');
    v_ben   bigint := (SELECT id FROM core.app_user WHERE email = 'ben.learner@example.com');
    v_carla bigint := (SELECT id FROM core.app_user WHERE email = 'carla.learner@example.com');
    v_group bigint := (SELECT id FROM core.study_group WHERE name = 'Tuesday evening group');
    v_link_ben_anna   bigint;
    v_link_carla_anna bigint;
    v_link_ben_self   bigint;
    v_run1 bigint := (SELECT r.id FROM core.parsing_run r JOIN core.material m ON m.id = r.material_id
                      WHERE m.file_location = 'materials/test/clothes-worksheet.pdf');
    v_e1 bigint; v_e2 bigint; v_e3 bigint; v_e6 bigint; v_e2_t1 bigint;
    v_topic_clothes bigint := (SELECT id FROM core.topic WHERE name = 'Clothes' AND owner_user_id IS NULL);
    v_topic_past    bigint;
    v_voc  bigint := (SELECT id FROM core.scale WHERE code = 'vocabulary');
    v_a2   bigint := (SELECT id FROM core.level_step WHERE name = 'A2');
    v_gap_bank bigint := (SELECT id FROM core.exercise_type WHERE code = 'gap_bank');
    v_typed    bigint := (SELECT id FROM core.exercise_type WHERE code = 'gap_bank_typed');
    v_proposal_open bigint; v_proposal_done bigint;
    v_lesson_group bigint;
    v_comp_lesson bigint; v_comp_matched bigint; v_part_ben bigint;
    v_code_ben_anna uuid; v_code_ben_self uuid;
BEGIN
    SELECT id INTO v_link_ben_anna FROM core.learning_link
    WHERE learner_user_id = v_ben AND teacher_user_id = v_anna AND ended_at IS NULL;
    SELECT id INTO v_link_carla_anna FROM core.learning_link
    WHERE learner_user_id = v_carla AND teacher_user_id = v_anna AND ended_at IS NULL;
    SELECT id INTO v_link_ben_self FROM core.learning_link
    WHERE learner_user_id = v_ben AND link_kind = 'self_directed';
    SELECT id INTO v_topic_past FROM core.topic WHERE name = 'Past simple' AND owner_user_id = v_anna;
    SELECT id INTO v_e1 FROM core.exercise WHERE parsing_run_id = v_run1 AND number_in_document = '1';
    SELECT id INTO v_e2 FROM core.exercise WHERE parsing_run_id = v_run1 AND number_in_document = '2';
    SELECT id INTO v_e3 FROM core.exercise WHERE parsing_run_id = v_run1 AND number_in_document = '3';
    SELECT id INTO v_e6 FROM core.exercise WHERE parsing_run_id = v_run1 AND number_in_document = '6';
    SELECT id INTO v_e2_t1 FROM core.task WHERE exercise_id = v_e2 AND number_in_exercise = 1;
    SELECT id INTO v_lesson_group FROM core.lesson WHERE study_group_id = v_group;
    SELECT random_code INTO v_code_ben_anna FROM core.learning_link_pseudonym WHERE learning_link_id = v_link_ben_anna;
    SELECT random_code INTO v_code_ben_self FROM core.learning_link_pseudonym WHERE learning_link_id = v_link_ben_self;

    INSERT INTO core.adaptation_proposal (learning_link_id, generated_at, status, decided_by, decided_at)
    VALUES (v_link_ben_anna, TIMESTAMPTZ '2026-11-15 08:00+02', 'proposed', NULL, NULL)
    RETURNING id INTO v_proposal_open;
    INSERT INTO core.adaptation_proposal_item (adaptation_proposal_id, item_kind, exercise_id, rationale_topic_id,
                                               rationale_period_from, rationale_period_to, added_by) VALUES
        (v_proposal_open, 'give_next',          v_e3, v_topic_clothes, DATE '2026-10-01', DATE '2026-11-14', 'system'),
        (v_proposal_open, 'return_to_revision', v_e1, v_topic_clothes, DATE '2026-10-01', DATE '2026-11-14', 'system');

    INSERT INTO core.adaptation_proposal (learning_link_id, generated_at, status, decided_by, decided_at)
    VALUES (v_link_ben_anna, TIMESTAMPTZ '2026-10-12 08:00+03', 'modified', 'user', TIMESTAMPTZ '2026-10-13 18:50+03')
    RETURNING id INTO v_proposal_done;
    INSERT INTO core.adaptation_proposal_item (adaptation_proposal_id, item_kind, exercise_id, rationale_topic_id,
                                               rationale_period_from, rationale_period_to, added_by, is_accepted,
                                               shown_as_exercise_type_id) VALUES
        (v_proposal_done, 'make_harder', v_e1, v_topic_clothes, DATE '2026-09-29', DATE '2026-10-11', 'system', true,  v_typed),
        (v_proposal_done, 'give_next',   v_e6, v_topic_clothes, DATE '2026-09-29', DATE '2026-10-11', 'system', false, NULL),
        (v_proposal_done, 'give_next',   v_e2, NULL,            NULL,              NULL,              'user',   true,  NULL);

    INSERT INTO core.topic_priority (learning_link_id, topic_id, raised_at, end_date)
    VALUES (v_link_ben_anna, v_topic_past, TIMESTAMPTZ '2026-11-16 17:15+02', DATE '2026-11-30');

    INSERT INTO core.competition (lesson_id, exercise_id, started_at, ended_at)
    VALUES (v_lesson_group, v_e2, TIMESTAMPTZ '2026-09-29 18:40+03', TIMESTAMPTZ '2026-09-29 18:50+03')
    RETURNING id INTO v_comp_lesson;
    INSERT INTO core.competition_participation (competition_id, learning_link_id, nickname, team_number, joined_at)
    VALUES (v_comp_lesson, v_link_ben_anna, 'Falcon', 1, TIMESTAMPTZ '2026-09-29 18:40+03')
    RETURNING id INTO v_part_ben;
    INSERT INTO core.competition_participation (competition_id, learning_link_id, nickname, team_number, joined_at)
    VALUES (v_comp_lesson, v_link_carla_anna, 'Otter', 2, TIMESTAMPTZ '2026-09-29 18:40+03');

    INSERT INTO core.competition (scale_id, level_step_id, exercise_type_id, started_at, ended_at, scored_task_count)
    VALUES (v_voc, v_a2, v_gap_bank, TIMESTAMPTZ '2026-11-16 16:00+02', NULL, 10)
    RETURNING id INTO v_comp_matched;
    INSERT INTO core.competition_participation (competition_id, learning_link_id, nickname, joined_at)
    VALUES (v_comp_matched, v_link_ben_self, 'Maple', TIMESTAMPTZ '2026-11-16 16:00+02');

    INSERT INTO core.answer (task_id, learning_link_id, content, result, attempt_number, response_time_ms,
                             active_time_ms, answered_at, answer_rating, competition_participation_id)
    VALUES (v_e2_t1, v_link_ben_anna, '{"parts": [{"id": "q1", "value": ["b"]}]}'::jsonb,
            'correct', 1, 12000, 12000, TIMESTAMPTZ '2026-09-29 18:42+03', 'moderate', v_part_ben);

    INSERT INTO stats.statistics_event (link_code, exercise_type_id, topic_id, is_correct, attempt_number,
                                        time_bucket, scale_id, level_step_id, device_type, event_date) VALUES
        (v_code_ben_anna, v_gap_bank, v_topic_clothes, true,  1, 'fast',     v_voc, v_a2, 'desktop', DATE '2026-10-03'),
        (v_code_ben_anna, v_gap_bank, v_topic_clothes, false, 1, 'slow',     v_voc, v_a2, 'desktop', DATE '2026-10-03'),
        (v_code_ben_anna, v_gap_bank, v_topic_clothes, true,  2, 'slow',     v_voc, v_a2, 'desktop', DATE '2026-10-03'),
        (v_code_ben_self, v_typed,    NULL,            true,  1, 'moderate', v_voc, v_a2, 'mobile',  DATE '2026-10-10');
END
$$;
--rollback DELETE FROM stats.statistics_event WHERE event_date IN (DATE '2026-10-03', DATE '2026-10-10');
--rollback DELETE FROM core.answer WHERE competition_participation_id IS NOT NULL AND learning_link_id IN (SELECT l.id FROM core.learning_link l JOIN core.app_user u ON u.id = l.learner_user_id WHERE u.email = 'ben.learner@example.com');
--rollback DELETE FROM core.competition WHERE id IN (SELECT p.competition_id FROM core.competition_participation p WHERE p.nickname IN ('Falcon', 'Otter', 'Maple'));
--rollback DELETE FROM core.topic_priority WHERE learning_link_id IN (SELECT l.id FROM core.learning_link l JOIN core.app_user u ON u.id = l.learner_user_id WHERE u.email = 'ben.learner@example.com');
--rollback DELETE FROM core.adaptation_proposal WHERE learning_link_id IN (SELECT l.id FROM core.learning_link l JOIN core.app_user u ON u.id = l.learner_user_id WHERE u.email = 'ben.learner@example.com');
