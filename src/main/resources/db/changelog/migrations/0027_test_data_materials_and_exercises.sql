--liquibase formatted sql

--changeset samitava:0027-test-materials-and-exercises context:test splitStatements:false
DO $$
DECLARE
    v_anna bigint;
    v_ben bigint;
    v_en bigint;
    v_a2 bigint;
    v_voc bigint;
    v_gram bigint;
    v_writ bigint;
    v_course_ben bigint;
    v_folder bigint;
    v_book bigint;
    v_m1 bigint;
    v_m2 bigint;
    v_m3 bigint;
    v_m4 bigint;
    v_m5 bigint;
    v_run1 bigint;
    v_run5 bigint;
    v_topic_clothes bigint;
    v_topic_past bigint;
    v_topic_travel bigint;
    v_e1 bigint;
    v_e2 bigint;
    v_e3 bigint;
    v_e4 bigint;
    v_e5 bigint;
    v_e6 bigint;
    v_e7 bigint;
    v_e8 bigint;
    v_e9 bigint;
    v_t bigint;
    v_t_example bigint;
    v_t_two_gaps bigint;
    v_t_choice2 bigint;
    v_t_alt bigint;
    v_img bigint;
    v_w_scarf bigint;
    v_w_gloves bigint;
    v_w_belt bigint;
    v_w_boots bigint;
BEGIN
    SELECT id INTO v_anna FROM core.app_user WHERE email = 'anna.teacher@example.com';
    SELECT id INTO v_ben FROM core.app_user WHERE email = 'ben.learner@example.com';
    SELECT id INTO v_en FROM core.language WHERE code = 'en';
    SELECT id INTO v_a2 FROM core.cefr_level WHERE name = 'A2';
    SELECT id INTO v_voc FROM core.scale WHERE code = 'vocabulary';
    SELECT id INTO v_gram FROM core.scale WHERE code = 'grammar';
    SELECT id INTO v_writ FROM core.scale WHERE code = 'writing';
    SELECT id INTO v_course_ben FROM core.course WHERE owner_user_id = v_ben;

    INSERT INTO core.folder (owner_user_id, name, folder_kind) VALUES (v_anna, 'Unit worksheets', 'ordinary')
    RETURNING id INTO v_folder;
    INSERT INTO core.folder (owner_user_id, name, folder_kind, split_method)
    VALUES (v_anna, 'Grammar handbook', 'book', 'by_contents')
    RETURNING id INTO v_book;

    INSERT INTO core.material (owner_user_id, name, file_location, file_size_bytes, page_count, has_text_layer,
                               cefr_level_id, study_language_id, processing_status, uploaded_at, folder_id)
    VALUES (v_anna, 'Clothes and accessories worksheet', 'materials/test/clothes-worksheet.pdf', 482133, 4, true,
            v_a2, v_en, 'parsed', TIMESTAMPTZ '2026-09-10 10:00+03', v_folder)
    RETURNING id INTO v_m1;
    INSERT INTO core.material (owner_user_id, name, file_location, file_size_bytes, page_count, has_text_layer,
                               study_language_id, processing_status, uploaded_at)
    VALUES (v_anna, 'Scanned handout', 'materials/test/scanned-handout.pdf', 2210448, 2, false,
            v_en, 'text_not_extracted', TIMESTAMPTZ '2026-09-10 11:00+03')
    RETURNING id INTO v_m2;
    INSERT INTO core.material (owner_user_id, name, file_location, file_size_bytes, page_count, has_text_layer,
                               cefr_level_id, study_language_id, processing_status, uploaded_at, folder_id,
                               part_number, source_page_from, source_page_to)
    VALUES (v_anna, 'Grammar handbook, part 1', 'materials/test/handbook-part-1.pdf', 5120000, 30, true,
            v_a2, v_en, 'parsed', TIMESTAMPTZ '2026-09-11 10:00+03', v_book, 1, 1, 30)
    RETURNING id INTO v_m3;
    INSERT INTO core.material (owner_user_id, name, file_location, file_size_bytes, page_count, has_text_layer,
                               cefr_level_id, study_language_id, processing_status, uploaded_at, folder_id,
                               part_number, source_page_from, source_page_to)
    VALUES (v_anna, 'Grammar handbook, part 2', 'materials/test/handbook-part-2.pdf', 2560000, 15, true,
            v_a2, v_en, 'not_parsed', TIMESTAMPTZ '2026-09-11 10:00+03', v_book, 2, 31, 45)
    RETURNING id INTO v_m4;
    INSERT INTO core.material (owner_user_id, name, file_location, file_size_bytes, page_count, has_text_layer,
                               cefr_level_id, study_language_id, processing_status, uploaded_at, course_id, archived_at)
    VALUES (v_ben, 'Travel phrases', 'materials/test/travel-phrases.pdf', 301200, 3, true,
            v_a2, v_en, 'parsed', TIMESTAMPTZ '2026-09-12 10:00+03', v_course_ben, NULL)
    RETURNING id INTO v_m5;

    INSERT INTO core.parsing_run (material_id, started_at, finished_at, outcome)
    VALUES (v_m1, TIMESTAMPTZ '2026-09-10 10:00:05+03', TIMESTAMPTZ '2026-09-10 10:00:41+03', 'completed')
    RETURNING id INTO v_run1;
    INSERT INTO core.parsing_run (material_id, started_at, finished_at, outcome) VALUES
        (v_m2, TIMESTAMPTZ '2026-09-10 11:00:05+03', TIMESTAMPTZ '2026-09-10 11:00:09+03', 'text_not_extracted'),
        (v_m3, TIMESTAMPTZ '2026-09-11 10:00:05+03', TIMESTAMPTZ '2026-09-11 10:05:05+03', 'timed_out'),
        (v_m3, TIMESTAMPTZ '2026-09-11 10:10:00+03', TIMESTAMPTZ '2026-09-11 10:12:30+03', 'completed');
    INSERT INTO core.parsing_run (material_id, started_at, finished_at, outcome)
    VALUES (v_m5, TIMESTAMPTZ '2026-09-12 10:00:05+03', TIMESTAMPTZ '2026-09-12 10:00:30+03', 'completed')
    RETURNING id INTO v_run5;

    INSERT INTO core.topic (name, owner_user_id) VALUES ('Clothes', NULL) RETURNING id INTO v_topic_clothes;
    INSERT INTO core.topic (name, owner_user_id) VALUES ('Past simple', v_anna) RETURNING id INTO v_topic_past;
    INSERT INTO core.topic (name, owner_user_id) VALUES ('Travel words', v_ben) RETURNING id INTO v_topic_travel;

    INSERT INTO core.exercise (parsing_run_id, exercise_type_id, topic_id, status, number_in_document,
                               instruction_text, shared_body, source_page, scale_id)
    VALUES (v_run1, (SELECT id FROM core.exercise_type WHERE code = 'gap_bank'), v_topic_clothes, 'approved', '1',
            'Complete the sentences with the words from the box.',
            '{"bank": [{"id": "w1", "text": "scarf"}, {"id": "w2", "text": "gloves"}, {"id": "w3", "text": "belt"}, {"id": "w4", "text": "boots"}, {"id": "w5", "text": "slippers"}]}'::jsonb, 1, v_voc)
    RETURNING id INTO v_e1;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e1, 1, 'She wore a warm ___ around her neck.',
            '{"parts": [{"id": "g1", "position": 16, "key": ["scarf"], "is_example": true}]}'::jsonb, 1, 1)
    RETURNING id INTO v_t_example;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e1, 2, 'He put on his ___ because his hands were cold.',
            '{"parts": [{"id": "g1", "position": 14, "key": ["gloves"], "is_example": false}]}'::jsonb, 1, 2)
    RETURNING id INTO v_t;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e1, 3, 'The trousers were too big, so he needed a ___.',
            '{"parts": [{"id": "g1", "position": 42, "key": ["belt"], "is_example": false}]}'::jsonb, 1, 3)
    RETURNING id INTO v_t;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e1, 4, 'Take your ___ off at the door and put on your ___.',
            '{"parts": [{"id": "g1", "position": 10, "key": ["boots"], "is_example": false}, {"id": "g2", "position": 46, "key": ["slippers"], "is_example": false}]}'::jsonb, 1, 4)
    RETURNING id INTO v_t_two_gaps;
    INSERT INTO core.exercise (parsing_run_id, exercise_type_id, topic_id, status, number_in_document,
                               instruction_text, shared_body, source_page, scale_id)
    VALUES (v_run1, (SELECT id FROM core.exercise_type WHERE code = 'single_choice'), v_topic_past, 'approved', '2',
            'Choose the correct form of the verb.',
            NULL, 2, v_gram)
    RETURNING id INTO v_e2;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e2, 1, 'Yesterday she ___ a red coat.',
            '{"parts": [{"id": "q1", "position": 14, "options": [{"id": "a", "text": "wear"}, {"id": "b", "text": "wore"}, {"id": "c", "text": "worn"}], "key": ["b"], "is_example": false}]}'::jsonb, 2, 1)
    RETURNING id INTO v_t;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e2, 2, 'They ___ new shoes last week.',
            '{"parts": [{"id": "q1", "position": 5, "options": [{"id": "a", "text": "buyed"}, {"id": "b", "text": "bought"}, {"id": "c", "text": "buy"}], "key": ["b"], "is_example": false}]}'::jsonb, 2, 2)
    RETURNING id INTO v_t_choice2;
    INSERT INTO core.exercise (parsing_run_id, exercise_type_id, topic_id, status, number_in_document,
                               instruction_text, shared_body, source_page, scale_id)
    VALUES (v_run1, (SELECT id FROM core.exercise_type WHERE code = 'matching'), v_topic_clothes, 'approved', '3',
            'Match the words with their meanings.',
            '{"right_items": [{"id": "r1", "text": "you wear it on your head"}, {"id": "r2", "text": "you wear them on your feet"}, {"id": "r3", "text": "it keeps your trousers up"}]}'::jsonb, 2, v_voc)
    RETURNING id INTO v_e3;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e3, 1, 'hat',
            '{"parts": [{"id": "p1", "key": ["r1"], "is_example": false}]}'::jsonb, 2, 11)
    RETURNING id INTO v_t;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e3, 2, 'socks',
            '{"parts": [{"id": "p1", "key": ["r2"], "is_example": false}]}'::jsonb, 2, 12)
    RETURNING id INTO v_t;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e3, 3, 'belt',
            '{"parts": [{"id": "p1", "key": ["r3"], "is_example": false}]}'::jsonb, 2, 13)
    RETURNING id INTO v_t;
    INSERT INTO core.exercise (parsing_run_id, exercise_type_id, topic_id, status, number_in_document,
                               instruction_text, shared_body, source_page, scale_id)
    VALUES (v_run1, NULL, NULL, 'draft', '4',
            'Look at the picture and talk to your partner.',
            NULL, 3, NULL)
    RETURNING id INTO v_e4;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e4, 1, 'What are the people in the picture wearing?',
            '{"parts": []}'::jsonb, 3, 1)
    RETURNING id INTO v_t;
    INSERT INTO core.exercise (parsing_run_id, exercise_type_id, topic_id, status, number_in_document,
                               instruction_text, shared_body, source_page, scale_id)
    VALUES (v_run1, (SELECT id FROM core.exercise_type WHERE code = 'free_text'), v_topic_clothes, 'approved', '5',
            'Write two or three sentences.',
            NULL, 3, v_writ)
    RETURNING id INTO v_e5;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e5, 1, 'Describe what you are wearing today.',
            '{"parts": [{"id": "f1", "sample": "Today I am wearing blue jeans and a grey jumper."}]}'::jsonb, 3, 2)
    RETURNING id INTO v_t;
    INSERT INTO core.exercise (parsing_run_id, exercise_type_id, topic_id, status, number_in_document,
                               instruction_text, shared_body, source_page, scale_id)
    VALUES (v_run1, (SELECT id FROM core.exercise_type WHERE code = 'gap_no_bank'), v_topic_clothes, 'approved', '6',
            'Complete the sentences. Use the words from exercise 1.',
            NULL, 4, v_voc)
    RETURNING id INTO v_e6;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e6, 1, 'It is cold outside, so put on a warm ___.',
            '{"parts": [{"id": "g1", "position": 37, "key": ["jumper", "sweater"], "is_example": false}]}'::jsonb, 4, 1)
    RETURNING id INTO v_t_alt;
    INSERT INTO core.exercise (parsing_run_id, exercise_type_id, topic_id, status, number_in_document,
                               instruction_text, shared_body, source_page, scale_id, excluded_at)
    VALUES (v_run1, (SELECT id FROM core.exercise_type WHERE code = 'word_search'), v_topic_clothes, 'draft', '7',
            'Find three clothes words in the grid.',
            '{"grid": {"rows": ["HATXQ", "BELTZ", "SOCKS"]}}'::jsonb, 4, v_voc, TIMESTAMPTZ '2026-09-10 10:20+03')
    RETURNING id INTO v_e7;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e7, 1, 'hat',
            '{"parts": [{"id": "s1", "key": ["HAT"], "cells": [{"row": 0, "column": 0}, {"row": 0, "column": 1}, {"row": 0, "column": 2}], "is_example": false}]}'::jsonb, 4, 2)
    RETURNING id INTO v_t;
    INSERT INTO core.exercise (parsing_run_id, exercise_type_id, topic_id, status, number_in_document,
                               instruction_text, shared_body, source_page, scale_id, source_exercise_id)
    VALUES (v_run1, (SELECT id FROM core.exercise_type WHERE code = 'word'), v_topic_clothes, 'draft', NULL,
            'Write the word for each meaning.',
            NULL, 2, v_voc, v_e3)
    RETURNING id INTO v_e8;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e8, 1, 'you wear it on your head',
            '{"parts": [{"id": "e1", "key": ["hat"], "is_example": false}]}'::jsonb, 2, 11)
    RETURNING id INTO v_t;
    INSERT INTO core.exercise (parsing_run_id, exercise_type_id, topic_id, status, number_in_document,
                               instruction_text, shared_body, source_page, scale_id)
    VALUES (v_run5, (SELECT id FROM core.exercise_type WHERE code = 'gap_bank'), v_topic_travel, 'approved', '1',
            'Complete the sentences with the words from the box.',
            '{"bank": [{"id": "w1", "text": "ticket"}, {"id": "w2", "text": "luggage"}]}'::jsonb, 1, v_voc)
    RETURNING id INTO v_e9;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e9, 1, 'I bought a ___ to Riga.',
            '{"parts": [{"id": "g1", "position": 11, "key": ["ticket"], "is_example": false}]}'::jsonb, 1, 1)
    RETURNING id INTO v_t;
    INSERT INTO core.task (exercise_id, number_in_exercise, task_text, body, source_page, position_on_page)
    VALUES (v_e9, 2, 'Our ___ was very heavy.',
            '{"parts": [{"id": "g1", "position": 4, "key": ["luggage"], "is_example": false}]}'::jsonb, 1, 2)
    RETURNING id INTO v_t;

    INSERT INTO core.exercise_dependency (dependent_exercise_id, prerequisite_exercise_id) VALUES (v_e6, v_e1);

    INSERT INTO core.flag (task_id, exercise_id, place_in_task, flag_reason_id, status, original_value,
                           placed_by_user_id, placed_at, closed_at) VALUES
        (v_t_example, NULL, 'g1', (SELECT id FROM core.flag_reason WHERE code = 'example_instead_of_answer'),
         'confirmed', NULL, NULL, TIMESTAMPTZ '2026-09-10 10:00:41+03', TIMESTAMPTZ '2026-09-10 10:15+03'),
        (NULL, v_e4, NULL, (SELECT id FROM core.flag_reason WHERE code = 'type_not_recognized'),
         'pending', NULL, NULL, TIMESTAMPTZ '2026-09-10 10:00:41+03', NULL),
        (NULL, v_e6, NULL, (SELECT id FROM core.flag_reason WHERE code = 'depends_on_previous'),
         'confirmed', NULL, NULL, TIMESTAMPTZ '2026-09-10 10:00:41+03', TIMESTAMPTZ '2026-09-10 10:16+03'),
        (v_t_alt, NULL, 'g1', (SELECT id FROM core.flag_reason WHERE code = 'multiple_answers'),
         'corrected', 'jumper/sweater', NULL, TIMESTAMPTZ '2026-09-10 10:00:41+03', TIMESTAMPTZ '2026-09-10 10:17+03'),
        (v_t_choice2, NULL, NULL, (SELECT id FROM core.flag_reason WHERE code = 'reported_as_wrong'),
         'pending', NULL, v_ben, TIMESTAMPTZ '2026-10-02 18:00+03', NULL);

    INSERT INTO core.image (exercise_id, file_location, origin, source_page, image_kind)
    VALUES (v_e7, 'images/test/word-search-grid.png', 'source', 4, 'grid');
    INSERT INTO core.image (exercise_id, file_location, origin, source_page, image_kind)
    VALUES (v_e4, 'images/test/people-in-the-park.png', 'source', 3, 'ordinary')
    RETURNING id INTO v_img;
    INSERT INTO core.image (exercise_id, file_location, origin, source_page, image_kind, source_image_id, confirmed_at)
    VALUES (v_e4, 'images/test/people-in-the-park-redrawn.png', 'redrawn', 3, 'ordinary', v_img, NULL);

    INSERT INTO core.word (language_id, spelling, transcription, explanation, reference_requested_at,
                           audio_location, audio_requested_at)
    VALUES (v_en, 'scarf', E'/sk\u0251\u02D0f/', 'a piece of cloth worn around the neck',
            TIMESTAMPTZ '2026-09-15 12:00+03', 'audio/test/scarf-us.mp3', TIMESTAMPTZ '2026-09-15 12:00+03')
    RETURNING id INTO v_w_scarf;
    INSERT INTO core.word (language_id, spelling, reference_requested_at)
    VALUES (v_en, 'gloves', TIMESTAMPTZ '2026-09-15 12:01+03')
    RETURNING id INTO v_w_gloves;
    INSERT INTO core.word (language_id, spelling) VALUES (v_en, 'belt') RETURNING id INTO v_w_belt;
    INSERT INTO core.word (language_id, spelling) VALUES (v_en, 'boots') RETURNING id INTO v_w_boots;

    INSERT INTO core.exercise_target_word (exercise_id, word_id) VALUES
        (v_e1, v_w_scarf), (v_e1, v_w_gloves), (v_e1, v_w_belt);
    INSERT INTO core.task_target_word (task_id, word_id) VALUES (v_t_two_gaps, v_w_boots);

    INSERT INTO core.presentation_item (exercise_id, task_id, item_kind, content, file_location, generated_at, confirmed_at) VALUES
        (v_e1, NULL, 'glossary', 'scarf, gloves, belt, boots, slippers', NULL,
         TIMESTAMPTZ '2026-09-10 10:30+03', TIMESTAMPTZ '2026-09-10 10:35+03'),
        (NULL, v_t_two_gaps, 'hint', 'One word is for outdoors, the other for home.', NULL,
         TIMESTAMPTZ '2026-09-10 10:31+03', NULL),
        (v_e5, NULL, 'illustration', NULL, 'presentation/test/wardrobe.png',
         TIMESTAMPTZ '2026-09-10 10:32+03', TIMESTAMPTZ '2026-09-10 10:36+03');
END
$$;
--rollback DELETE FROM core.material WHERE file_location LIKE 'materials/test/%';
--rollback DELETE FROM core.folder WHERE name IN ('Unit worksheets', 'Grammar handbook') AND owner_user_id = (SELECT id FROM core.app_user WHERE email = 'anna.teacher@example.com');
--rollback DELETE FROM core.topic WHERE name IN ('Clothes', 'Past simple', 'Travel words');
--rollback DELETE FROM core.word WHERE spelling IN ('scarf', 'gloves', 'belt', 'boots') AND language_id = (SELECT id FROM core.language WHERE code = 'en');
