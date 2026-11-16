--liquibase formatted sql

--changeset samitava:0040-test-competition-answers context:test splitStatements:false
-- The lesson competition had only the practice answer of one participant, so its result could not be shown.
DO $$
DECLARE
    v_falcon bigint;
    v_otter bigint;
    v_link_falcon bigint;
    v_link_otter bigint;
    v_task1 bigint;
    v_task2 bigint;
BEGIN
    SELECT id, learning_link_id INTO STRICT v_falcon, v_link_falcon FROM core.competition_participation WHERE nickname = 'Falcon';
    SELECT id, learning_link_id INTO STRICT v_otter, v_link_otter FROM core.competition_participation WHERE nickname = 'Otter';
    SELECT t.id INTO STRICT v_task1
      FROM core.task t JOIN core.exercise e ON e.id = t.exercise_id
      JOIN core.competition c ON c.exercise_id = e.id
      JOIN core.competition_participation cp ON cp.competition_id = c.id
     WHERE cp.id = v_falcon AND t.number_in_exercise = 1;
    SELECT t.id INTO STRICT v_task2
      FROM core.task t JOIN core.exercise e ON e.id = t.exercise_id
      JOIN core.competition c ON c.exercise_id = e.id
      JOIN core.competition_participation cp ON cp.competition_id = c.id
     WHERE cp.id = v_falcon AND t.number_in_exercise = 2;

    INSERT INTO core.answer (task_id, learning_link_id, content, result, attempt_number, response_time_ms,
                             active_time_ms, answered_at, answer_rating, competition_participation_id)
    VALUES (v_task2, v_link_falcon, '{"parts": [{"id": "q1", "value": ["b"]}]}'::jsonb,
            'correct', 1, 9000, 9000, TIMESTAMPTZ '2026-09-29 18:44+03', 'fast', v_falcon),
           (v_task1, v_link_otter, '{"parts": [{"id": "q1", "value": ["c"]}]}'::jsonb,
            'incorrect', 1, 15000, 15000, TIMESTAMPTZ '2026-09-29 18:42+03', 'error', v_otter),
           (v_task2, v_link_otter, '{"parts": [{"id": "q1", "value": ["a"]}]}'::jsonb,
            'incorrect', 1, 21000, 20000, TIMESTAMPTZ '2026-09-29 18:45+03', 'error', v_otter);
END
$$;
--rollback DELETE FROM core.answer WHERE competition_participation_id IN (SELECT id FROM core.competition_participation WHERE nickname IN ('Falcon', 'Otter')) AND answered_at IN (TIMESTAMPTZ '2026-09-29 18:44+03', TIMESTAMPTZ '2026-09-29 18:45+03');
--rollback DELETE FROM core.answer WHERE competition_participation_id IN (SELECT id FROM core.competition_participation WHERE nickname = 'Otter') AND answered_at = TIMESTAMPTZ '2026-09-29 18:42+03';
