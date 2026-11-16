--liquibase formatted sql

--changeset samitava:0039-test-edge-cases context:test splitStatements:false
DO $$
DECLARE
    v_en bigint;
    v_gb bigint;
    v_us bigint;
    v_ben bigint;
    v_carla bigint;
    v_anna bigint;
    v_run bigint;
    v_voc bigint;
    v_topic bigint;
    v_scarf bigint;
    v_gloves bigint;
    v_e_picture bigint;
    v_e_grid bigint;
    v_e_meaning bigint;
    v_e_no_bank bigint;
    v_e_manual bigint;
    v_t_meaning bigint;
    v_t_two_gaps bigint;
    v_link bigint;
BEGIN
    SELECT id INTO STRICT v_en FROM core.language WHERE code = 'en';
    SELECT id INTO STRICT v_gb FROM core.pronunciation_variant WHERE code = 'en-GB';
    SELECT id INTO STRICT v_us FROM core.pronunciation_variant WHERE code = 'en-US';
    SELECT id INTO STRICT v_ben FROM core.app_user WHERE email = 'ben.learner@example.com';
    SELECT id INTO STRICT v_carla FROM core.app_user WHERE email = 'carla.learner@example.com';
    SELECT id INTO STRICT v_anna FROM core.app_user WHERE email = 'anna.teacher@example.com';
    SELECT id INTO STRICT v_voc FROM core.scale WHERE code = 'vocabulary';
    SELECT pr.id INTO STRICT v_run
      FROM core.parsing_run pr JOIN core.material m ON m.id = pr.material_id
     WHERE m.file_location = 'materials/test/clothes-worksheet.pdf';
    SELECT id INTO STRICT v_topic FROM core.topic WHERE name = 'Clothes' AND owner_user_id IS NULL;
    SELECT id INTO STRICT v_scarf FROM core.word WHERE spelling = 'scarf' AND language_id = v_en;
    SELECT id INTO STRICT v_gloves FROM core.word WHERE spelling = 'gloves' AND language_id = v_en;
    SELECT id INTO STRICT v_e_picture FROM core.exercise WHERE parsing_run_id = v_run AND number_in_document = '4';
    SELECT id INTO STRICT v_e_no_bank FROM core.exercise WHERE parsing_run_id = v_run AND number_in_document = '6';
    SELECT id INTO STRICT v_e_grid FROM core.exercise WHERE parsing_run_id = v_run AND number_in_document = '7';
    SELECT id INTO STRICT v_e_meaning FROM core.exercise
     WHERE parsing_run_id = v_run AND instruction_text = 'Write the word for each meaning.';
    SELECT id INTO STRICT v_t_meaning FROM core.task WHERE exercise_id = v_e_meaning AND number_in_exercise = 1;
    SELECT t.id INTO STRICT v_t_two_gaps
      FROM core.task t JOIN core.exercise e ON e.id = t.exercise_id
     WHERE e.parsing_run_id = v_run AND e.number_in_document = '1' AND t.number_in_exercise = 4;
    SELECT id INTO STRICT v_link FROM core.learning_link
     WHERE learner_user_id = v_ben AND teacher_user_id = v_anna AND ended_at IS NULL;

    -- Pronunciation: one word in both variants, one word with a transcription and no audio,
    -- one learner per variant; the third learner has made no choice.
    UPDATE core.word_pronunciation SET audio_location = 'audio/test/scarf-gb.mp3'
     WHERE word_id = v_scarf AND pronunciation_variant_id = v_gb;
    INSERT INTO core.word_pronunciation (word_id, language_id, pronunciation_variant_id, transcription, audio_location, audio_requested_at)
    VALUES (v_scarf, v_en, v_us, E'/sk\u0251\u02D0rf/', 'audio/test/scarf-us.mp3', TIMESTAMPTZ '2026-09-15 12:00:05+03'),
           (v_gloves, v_en, v_gb, E'/\u0261l\u028Cvz/', NULL, NULL);
    INSERT INTO core.pronunciation_choice (learner_user_id, language_id, pronunciation_variant_id)
    VALUES (v_ben, v_en, v_gb),
           (v_carla, v_en, v_us);

    -- A typed exercise where the author accepts typos.
    UPDATE core.exercise SET is_typo_tolerated = true WHERE id = v_e_no_bank;

    -- Revision per part: in the task with two gaps the first gap is known, the second one comes back tomorrow.
    UPDATE core.revision_record SET part_id = 'g2'
     WHERE learning_link_id = v_link AND task_id = v_t_two_gaps AND part_id IS NULL;
    INSERT INTO core.revision_record (task_id, learning_link_id, part_id, next_revision_date, current_interval_days, ease)
    VALUES (v_t_two_gaps, v_link, 'g1', DATE '2026-11-22', 6, 2.50);

    -- The four flag reasons that the earlier test data did not use.
    INSERT INTO core.flag (task_id, exercise_id, place_in_task, flag_reason_id, status, original_value, placed_by_user_id, placed_at, closed_at)
    VALUES (NULL, v_e_grid, NULL, (SELECT id FROM core.flag_reason WHERE code = 'text_in_image'),
            'pending', NULL, NULL, TIMESTAMPTZ '2026-09-10 10:00:41+03', NULL),
           (NULL, v_e_picture, NULL, (SELECT id FROM core.flag_reason WHERE code = 'no_text_layer'),
            'pending', NULL, NULL, TIMESTAMPTZ '2026-09-10 10:00:41+03', NULL),
           (NULL, v_e_meaning, NULL, (SELECT id FROM core.flag_reason WHERE code = 'key_not_matched'),
            'pending', '8 cap', NULL, TIMESTAMPTZ '2026-09-10 10:00:41+03', NULL),
           (v_t_meaning, NULL, 'e1', (SELECT id FROM core.flag_reason WHERE code = 'enter_manually'),
            'corrected', NULL, NULL, TIMESTAMPTZ '2026-09-10 10:00:41+03', TIMESTAMPTZ '2026-09-10 10:18:00+03');

    -- An exercise the parser could not type: the author set the type by hand and the flag is closed.
    INSERT INTO core.exercise (parsing_run_id, exercise_type_id, topic_id, status, number_in_document,
                               instruction_text, shared_body, source_page, scale_id)
    VALUES (v_run, (SELECT id FROM core.exercise_type WHERE code = 'word'), v_topic, 'approved', '9',
            'What is it?',
            NULL, 4, v_voc)
    RETURNING id INTO v_e_manual;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e_manual, 1, 'You wear them on your feet at home.',
            '{"parts": [{"id": "e1", "key": ["slippers"], "is_example": false}]}'::jsonb, 4, 1);
    INSERT INTO core.flag (task_id, exercise_id, place_in_task, flag_reason_id, status, original_value, placed_by_user_id, placed_at, closed_at)
    VALUES (NULL, v_e_manual, NULL, (SELECT id FROM core.flag_reason WHERE code = 'type_not_recognized'),
            'corrected', NULL, NULL, TIMESTAMPTZ '2026-09-10 10:00:41+03', TIMESTAMPTZ '2026-09-10 10:20:00+03');
END
$$;
--rollback DELETE FROM core.exercise WHERE number_in_document = '9' AND instruction_text = 'What is it?' AND parsing_run_id IN (SELECT pr.id FROM core.parsing_run pr JOIN core.material m ON m.id = pr.material_id WHERE m.file_location = 'materials/test/clothes-worksheet.pdf');
--rollback DELETE FROM core.flag WHERE flag_reason_id IN (SELECT id FROM core.flag_reason WHERE code IN ('text_in_image', 'no_text_layer', 'key_not_matched', 'enter_manually')) AND placed_at = TIMESTAMPTZ '2026-09-10 10:00:41+03';
--rollback DELETE FROM core.revision_record WHERE part_id = 'g1' AND learning_link_id IN (SELECT ll.id FROM core.learning_link ll JOIN core.app_user u ON u.id = ll.learner_user_id WHERE u.email = 'ben.learner@example.com');
--rollback UPDATE core.revision_record SET part_id = NULL WHERE part_id = 'g2' AND learning_link_id IN (SELECT ll.id FROM core.learning_link ll JOIN core.app_user u ON u.id = ll.learner_user_id WHERE u.email = 'ben.learner@example.com');
--rollback UPDATE core.exercise SET is_typo_tolerated = false WHERE is_typo_tolerated AND parsing_run_id IN (SELECT pr.id FROM core.parsing_run pr JOIN core.material m ON m.id = pr.material_id WHERE m.file_location = 'materials/test/clothes-worksheet.pdf');
--rollback DELETE FROM core.pronunciation_choice WHERE learner_user_id IN (SELECT id FROM core.app_user WHERE email IN ('ben.learner@example.com', 'carla.learner@example.com'));
--rollback DELETE FROM core.word_pronunciation WHERE pronunciation_variant_id = (SELECT id FROM core.pronunciation_variant WHERE code = 'en-US') AND word_id IN (SELECT id FROM core.word WHERE spelling = 'scarf');
--rollback DELETE FROM core.word_pronunciation WHERE word_id IN (SELECT id FROM core.word WHERE spelling = 'gloves');
--rollback UPDATE core.word_pronunciation SET audio_location = 'audio/test/scarf-us.mp3' WHERE word_id IN (SELECT id FROM core.word WHERE spelling = 'scarf');
