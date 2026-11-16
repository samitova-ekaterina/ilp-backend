--liquibase formatted sql

--changeset samitava:0028-test-lessons-and-history context:test splitStatements:false
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
    v_run5 bigint := (SELECT r.id FROM core.parsing_run r JOIN core.material m ON m.id = r.material_id
                      WHERE m.file_location = 'materials/test/travel-phrases.pdf');
    v_e1 bigint; v_e2 bigint; v_e5 bigint; v_e6 bigint; v_e9 bigint;
    v_e1_t2 bigint; v_e1_t3 bigint; v_e1_t4 bigint; v_e2_t1 bigint; v_e2_t2 bigint;
    v_e5_t1 bigint; v_e6_t1 bigint; v_e9_t1 bigint; v_e9_t2 bigint;
    v_lesson_group bigint; v_lesson_ben bigint; v_lesson_ex_carla bigint;
    v_hw_group bigint; v_hw_ben bigint; v_assign_ben bigint;
    v_voc  bigint := (SELECT id FROM core.scale WHERE code = 'vocabulary');
    v_gram bigint := (SELECT id FROM core.scale WHERE code = 'grammar');
    v_writ bigint := (SELECT id FROM core.scale WHERE code = 'writing');
    v_sp   bigint := (SELECT id FROM core.scale WHERE code = 'speech');
    v_a1 bigint := (SELECT id FROM core.level_step WHERE name = 'A1');
    v_a2 bigint := (SELECT id FROM core.level_step WHERE name = 'A2');
    v_b1 bigint := (SELECT id FROM core.level_step WHERE name = 'B1');
    v_sl_voc bigint; v_sl_gram bigint;
    v_typed bigint := (SELECT id FROM core.exercise_type WHERE code = 'gap_bank_typed');
BEGIN
    SELECT id INTO v_link_ben_anna FROM core.learning_link
    WHERE learner_user_id = v_ben AND teacher_user_id = v_anna AND ended_at IS NULL;
    SELECT id INTO v_link_carla_anna FROM core.learning_link
    WHERE learner_user_id = v_carla AND teacher_user_id = v_anna AND ended_at IS NULL;
    SELECT id INTO v_link_ben_self FROM core.learning_link
    WHERE learner_user_id = v_ben AND link_kind = 'self_directed';

    SELECT id INTO v_e1 FROM core.exercise WHERE parsing_run_id = v_run1 AND number_in_document = '1';
    SELECT id INTO v_e2 FROM core.exercise WHERE parsing_run_id = v_run1 AND number_in_document = '2';
    SELECT id INTO v_e5 FROM core.exercise WHERE parsing_run_id = v_run1 AND number_in_document = '5';
    SELECT id INTO v_e6 FROM core.exercise WHERE parsing_run_id = v_run1 AND number_in_document = '6';
    SELECT id INTO v_e9 FROM core.exercise WHERE parsing_run_id = v_run5 AND number_in_document = '1';
    SELECT id INTO v_e1_t2 FROM core.task WHERE exercise_id = v_e1 AND number_in_exercise = 2;
    SELECT id INTO v_e1_t3 FROM core.task WHERE exercise_id = v_e1 AND number_in_exercise = 3;
    SELECT id INTO v_e1_t4 FROM core.task WHERE exercise_id = v_e1 AND number_in_exercise = 4;
    SELECT id INTO v_e2_t1 FROM core.task WHERE exercise_id = v_e2 AND number_in_exercise = 1;
    SELECT id INTO v_e2_t2 FROM core.task WHERE exercise_id = v_e2 AND number_in_exercise = 2;
    SELECT id INTO v_e5_t1 FROM core.task WHERE exercise_id = v_e5 AND number_in_exercise = 1;
    SELECT id INTO v_e6_t1 FROM core.task WHERE exercise_id = v_e6 AND number_in_exercise = 1;
    SELECT id INTO v_e9_t1 FROM core.task WHERE exercise_id = v_e9 AND number_in_exercise = 1;
    SELECT id INTO v_e9_t2 FROM core.task WHERE exercise_id = v_e9 AND number_in_exercise = 2;

    INSERT INTO core.lesson (study_group_id, learning_link_id, started_at, ended_at)
    VALUES (v_group, NULL, TIMESTAMPTZ '2026-09-29 18:00+03', TIMESTAMPTZ '2026-09-29 19:00+03')
    RETURNING id INTO v_lesson_group;
    INSERT INTO core.lesson (study_group_id, learning_link_id, started_at, ended_at)
    VALUES (NULL, v_link_ben_anna, TIMESTAMPTZ '2026-11-16 17:00+02', NULL)
    RETURNING id INTO v_lesson_ben;

    INSERT INTO core.lesson_exercise (lesson_id, exercise_id, shown_to_learning_link_id, opened_at)
    VALUES (v_lesson_group, v_e1, NULL, TIMESTAMPTZ '2026-09-29 18:05+03');
    INSERT INTO core.lesson_exercise (lesson_id, exercise_id, shown_to_learning_link_id, opened_at)
    VALUES (v_lesson_group, v_e2, v_link_carla_anna, TIMESTAMPTZ '2026-09-29 18:30+03')
    RETURNING id INTO v_lesson_ex_carla;

    INSERT INTO core.homework (assigned_by_user_id, study_group_id, due_at, assigned_at)
    VALUES (v_anna, v_group, TIMESTAMPTZ '2026-10-06 18:00+03', TIMESTAMPTZ '2026-09-29 19:00+03')
    RETURNING id INTO v_hw_group;
    INSERT INTO core.homework_exercise (homework_id, exercise_id, sort_order, item_kind) VALUES
        (v_hw_group, v_e1, 1, 'main'),
        (v_hw_group, v_e6, 2, 'main'),
        (v_hw_group, v_e5, 3, 'additional');
    INSERT INTO core.homework_assignment (homework_id, learning_link_id, personal_note, completed_at)
    VALUES (v_hw_group, v_link_ben_anna, 'Pay attention to spelling.', TIMESTAMPTZ '2026-10-03 20:15+03')
    RETURNING id INTO v_assign_ben;
    INSERT INTO core.homework_assignment (homework_id, learning_link_id, personal_note, completed_at)
    VALUES (v_hw_group, v_link_carla_anna, NULL, NULL);

    INSERT INTO core.homework (assigned_by_user_id, study_group_id, due_at, assigned_at)
    VALUES (v_anna, NULL, TIMESTAMPTZ '2026-10-20 18:00+03', TIMESTAMPTZ '2026-10-13 19:00+03')
    RETURNING id INTO v_hw_ben;
    INSERT INTO core.homework_task (homework_id, task_id, sort_order, item_kind) VALUES
        (v_hw_ben, v_e2_t1, 1, 'main'),
        (v_hw_ben, v_e2_t2, 2, 'additional');
    INSERT INTO core.homework_assignment (homework_id, learning_link_id, personal_note, completed_at)
    VALUES (v_hw_ben, v_link_ben_anna, NULL, NULL);

    INSERT INTO core.answer (task_id, learning_link_id, homework_assignment_id, content, result, attempt_number,
                             response_time_ms, active_time_ms, answered_at, answer_change_count, answer_rating,
                             error_type_id) VALUES
        (v_e1_t2, v_link_ben_anna, v_assign_ben, '{"parts": [{"id": "g1", "value": "gloves"}]}'::jsonb,
         'correct', 1, 4200, 4200, TIMESTAMPTZ '2026-10-03 20:01+03', 0, 'fast', NULL),
        (v_e1_t3, v_link_ben_anna, v_assign_ben, '{"parts": [{"id": "g1", "value": "boots"}]}'::jsonb,
         'incorrect', 1, 15300, 11000, TIMESTAMPTZ '2026-10-03 20:03+03', 0, 'error',
         (SELECT id FROM core.error_type WHERE code = 'word_choice')),
        (v_e1_t3, v_link_ben_anna, v_assign_ben, '{"parts": [{"id": "g1", "value": "belt"}]}'::jsonb,
         'correct', 2, 21000, 16500, TIMESTAMPTZ '2026-10-03 20:04+03', 1, 'slow_and_changed', NULL),
        (v_e1_t4, v_link_ben_anna, v_assign_ben,
         '{"parts": [{"id": "g1", "value": "boots"}, {"id": "g2", "value": "scarf"}]}'::jsonb,
         'incorrect', 1, 18000, 18000, TIMESTAMPTZ '2026-10-03 20:06+03', 2, 'error',
         (SELECT id FROM core.error_type WHERE code = 'word_choice')),
        (v_e6_t1, v_link_ben_anna, v_assign_ben, '{"parts": [{"id": "g1", "value": "Sweater "}]}'::jsonb,
         'correct', 1, 9000, 9000, TIMESTAMPTZ '2026-10-03 20:10+03', 0, 'moderate', NULL),
        (v_e5_t1, v_link_ben_anna, v_assign_ben,
         '{"parts": [{"id": "f1", "value": "Today I am wearing a white shirt and black trousers."}]}'::jsonb,
         'awaiting_review', 1, 95000, 60000, TIMESTAMPTZ '2026-10-03 20:14+03', 3, NULL, NULL);

    INSERT INTO core.answer (task_id, learning_link_id, content, result, attempt_number, response_time_ms,
                             active_time_ms, answered_at, answer_rating, lesson_exercise_id)
    VALUES (v_e2_t1, v_link_carla_anna, '{"parts": [{"id": "q1", "value": ["b"]}]}'::jsonb,
            'correct', 1, 6000, 6000, TIMESTAMPTZ '2026-09-29 18:32+03', 'moderate', v_lesson_ex_carla);

    INSERT INTO core.answer (task_id, learning_link_id, content, result, attempt_number, response_time_ms,
                             active_time_ms, answered_at, answer_rating, reviewed_at)
    VALUES (v_e5_t1, v_link_carla_anna,
            '{"parts": [{"id": "f1", "value": "I am wearing a green dress."}]}'::jsonb,
            'correct', 1, 80000, 80000, TIMESTAMPTZ '2026-09-30 17:00+03', 'moderate',
            TIMESTAMPTZ '2026-10-01 09:00+03');

    INSERT INTO core.answer (task_id, learning_link_id, content, result, attempt_number, response_time_ms,
                             active_time_ms, answered_at, answer_rating, shown_as_exercise_type_id)
    VALUES (v_e9_t1, v_link_ben_self, '{"parts": [{"id": "g1", "value": "ticket"}]}'::jsonb,
            'correct', 1, 7000, 7000, TIMESTAMPTZ '2026-10-10 08:00+03', 'moderate', v_typed);

    INSERT INTO core.revision_record (task_id, learning_link_id, next_revision_date, current_interval_days, ease,
                                      deferred_at, deferral_end_date) VALUES
        (v_e1_t2, v_link_ben_anna, DATE '2026-11-20', 16, 2.65, NULL, NULL),
        (v_e1_t3, v_link_ben_anna, DATE '2026-11-17', 2, 2.35, NULL, NULL),
        (v_e1_t4, v_link_ben_anna, DATE '2026-11-17', 1, 1.30, NULL, NULL),
        (v_e9_t2, v_link_ben_self, DATE '2026-11-25', 1, 1.90, TIMESTAMPTZ '2026-11-10 08:00+02', DATE '2026-11-24');

    INSERT INTO core.scale_level (learning_link_id, scale_id, entry_level_step_id, current_level_step_id)
    VALUES (v_link_ben_anna, v_voc, v_a2, v_b1) RETURNING id INTO v_sl_voc;
    INSERT INTO core.scale_level (learning_link_id, scale_id, entry_level_step_id, current_level_step_id)
    VALUES (v_link_ben_anna, v_gram, v_a1, v_a2) RETURNING id INTO v_sl_gram;
    INSERT INTO core.scale_level (learning_link_id, scale_id, entry_level_step_id, current_level_step_id) VALUES
        (v_link_ben_anna,   v_writ, v_a2, v_a2),
        (v_link_ben_anna,   v_sp,   NULL, NULL),
        (v_link_carla_anna, v_voc,  v_a1, v_a1),
        (v_link_ben_self,   v_voc,  v_a2, v_a2);

    INSERT INTO core.level_change (scale_level_id, previous_level_step_id, new_level_step_id, changed_at,
                                   changed_by, shown_to_learner_at) VALUES
        (v_sl_voc,  v_a2, v_b1, TIMESTAMPTZ '2026-10-20 19:00+03', 'user',   TIMESTAMPTZ '2026-10-20 19:30+03'),
        (v_sl_gram, v_a1, v_a2, TIMESTAMPTZ '2026-11-10 10:00+02', 'system', NULL);

    INSERT INTO core.oral_error (learning_link_id, lesson_id, task_id, topic_id, scale_id, phrase, recorded_at,
                                 error_type_id) VALUES
        (v_link_ben_anna, v_lesson_ben, NULL,
         (SELECT id FROM core.topic WHERE name = 'Past simple' AND owner_user_id = v_anna), v_sp,
         'I goed to the shop', TIMESTAMPTZ '2026-11-16 17:10+02', (SELECT id FROM core.error_type WHERE code = 'form')),
        (v_link_ben_anna, NULL, v_e2_t1, NULL, v_sp, NULL, TIMESTAMPTZ '2026-10-21 18:00+03', NULL);

    INSERT INTO core.note (learning_link_id, lesson_id, note_text, written_at) VALUES
        (v_link_ben_anna, v_lesson_ben, 'Mixes up past forms of irregular verbs.', TIMESTAMPTZ '2026-11-16 17:20+02'),
        (v_link_ben_anna, NULL, 'Wants more speaking practice.', TIMESTAMPTZ '2026-10-01 12:00+03');
END
$$;
--rollback DELETE FROM core.answer WHERE learning_link_id IN (SELECT l.id FROM core.learning_link l JOIN core.app_user u ON u.id = l.learner_user_id WHERE u.email IN ('ben.learner@example.com', 'carla.learner@example.com'));
--rollback DELETE FROM core.revision_record WHERE learning_link_id IN (SELECT l.id FROM core.learning_link l JOIN core.app_user u ON u.id = l.learner_user_id WHERE u.email = 'ben.learner@example.com');
--rollback DELETE FROM core.scale_level WHERE learning_link_id IN (SELECT l.id FROM core.learning_link l JOIN core.app_user u ON u.id = l.learner_user_id WHERE u.email IN ('ben.learner@example.com', 'carla.learner@example.com'));
--rollback DELETE FROM core.oral_error WHERE learning_link_id IN (SELECT l.id FROM core.learning_link l JOIN core.app_user u ON u.id = l.learner_user_id WHERE u.email = 'ben.learner@example.com');
--rollback DELETE FROM core.note WHERE learning_link_id IN (SELECT l.id FROM core.learning_link l JOIN core.app_user u ON u.id = l.learner_user_id WHERE u.email = 'ben.learner@example.com');
--rollback DELETE FROM core.homework WHERE assigned_by_user_id = (SELECT id FROM core.app_user WHERE email = 'anna.teacher@example.com');
--rollback DELETE FROM core.lesson WHERE study_group_id = (SELECT id FROM core.study_group WHERE name = 'Tuesday evening group') OR learning_link_id IN (SELECT l.id FROM core.learning_link l JOIN core.app_user u ON u.id = l.learner_user_id WHERE u.email = 'ben.learner@example.com');
