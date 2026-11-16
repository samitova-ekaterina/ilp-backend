-- Scenario queries for the ILP database.
-- Each query answers a question of one story of the product and runs on the test data
-- (migrations with the context "test"). The stories are grouped in epics of the requirements:
-- 1 Accounts and access, 2 Preparing a material, 3 History of a learner, 4 Adaptation,
-- 5 Lesson and homework, 6 Practice and revision, 7 Competitions and grouping.
-- The number of rows every query returns on the test data is given in a comment after it.
-- Run: psql -U ilp_owner -d ilp -f scenario-queries.sql

-- Q01. Epic 1, registration with consent: users, the consent age of their country and their consents in force.
SELECT u.email, u.age_group, c.code AS country, c.consent_age,
       string_agg(cn.consent_kind || ' v' || pv.version_number, ', ' ORDER BY cn.consent_kind) AS consents_in_force
  FROM core.app_user u
  JOIN core.country c ON c.id = u.country_id
  LEFT JOIN core.consent cn ON cn.app_user_id = u.id AND cn.withdrawn_at IS NULL
  LEFT JOIN core.policy_version pv ON pv.id = cn.policy_version_id
 GROUP BY u.id, u.email, u.age_group, c.code, c.consent_age
 ORDER BY u.email;
-- Result on the test data: 5 rows.

-- Q02. Epic 1, a teacher sees only the work on own assignments: learners of one teacher and their homework.
SELECT COALESCE(lu.display_name, '(no name)') AS learner, g.name AS study_group,
       count(ha.id) AS assigned, count(ha.completed_at) AS completed
  FROM core.learning_link ll
  JOIN core.app_user tu ON tu.id = ll.teacher_user_id
  JOIN core.app_user lu ON lu.id = ll.learner_user_id
  LEFT JOIN core.group_membership gm ON gm.learning_link_id = ll.id AND gm.left_at IS NULL
  LEFT JOIN core.study_group g ON g.id = gm.study_group_id
  LEFT JOIN core.homework_assignment ha ON ha.learning_link_id = ll.id
 WHERE tu.email = 'anna.teacher@example.com' AND ll.ended_at IS NULL
 GROUP BY lu.id, lu.display_name, g.name
 ORDER BY learner;
-- Result on the test data: 2 rows.

-- Q03. Epic 2, parsing report: exercises, tasks and open flags of every material.
SELECT m.name AS material, m.processing_status,
       count(DISTINCT e.id) AS exercises,
       count(DISTINCT e.id) FILTER (WHERE e.status = 'approved') AS approved,
       count(DISTINCT t.id) AS tasks,
       count(DISTINCT f.id) FILTER (WHERE f.status = 'pending') AS pending_flags
  FROM core.material m
  LEFT JOIN core.parsing_run pr ON pr.material_id = m.id AND pr.outcome = 'completed'
  LEFT JOIN core.exercise e ON e.parsing_run_id = pr.id
  LEFT JOIN core.task t ON t.exercise_id = e.id
  LEFT JOIN core.flag f ON f.exercise_id = e.id OR f.task_id = t.id
 GROUP BY m.id, m.name, m.processing_status
 ORDER BY m.name;
-- Result on the test data: 5 rows.

-- Q04. Epic 2, confirm only what is flagged: pending flags of one material with the place in the document.
SELECT fr.name AS reason, e.number_in_document, e.source_page, t.number_in_exercise, f.place_in_task, f.original_value
  FROM core.flag f
  JOIN core.flag_reason fr ON fr.id = f.flag_reason_id
  LEFT JOIN core.task t ON t.id = f.task_id
  JOIN core.exercise e ON e.id = COALESCE(f.exercise_id, t.exercise_id)
  JOIN core.parsing_run pr ON pr.id = e.parsing_run_id
  JOIN core.material m ON m.id = pr.material_id
 WHERE m.file_location = 'materials/test/clothes-worksheet.pdf' AND f.status = 'pending'
 ORDER BY e.source_page, e.number_in_document NULLS LAST;
-- Result on the test data: 5 rows.

-- Q05. Epic 3, learner card: level on every scale with the entry level and the last change.
SELECT s.name AS scale, el.name AS entry_level, cl.name AS current_level,
       lc.changed_at AS last_change, lc.changed_by
  FROM core.learning_link ll
  JOIN core.app_user lu ON lu.id = ll.learner_user_id
  JOIN core.app_user tu ON tu.id = ll.teacher_user_id
  JOIN core.scale_level sl ON sl.learning_link_id = ll.id
  JOIN core.scale s ON s.id = sl.scale_id
  LEFT JOIN core.cefr_level el ON el.id = sl.entry_cefr_level_id
  LEFT JOIN core.cefr_level cl ON cl.id = sl.current_cefr_level_id
  LEFT JOIN LATERAL (SELECT changed_at, changed_by FROM core.level_change
                      WHERE scale_level_id = sl.id ORDER BY changed_at DESC LIMIT 1) lc ON true
 WHERE lu.email = 'ben.learner@example.com' AND tu.email = 'anna.teacher@example.com' AND ll.ended_at IS NULL
 ORDER BY s.display_order;
-- Result on the test data: 4 rows.

-- Q06. Epic 3, attempts and response time: answers of one learning link by topic.
SELECT COALESCE(tp.name, 'no topic') AS topic,
       count(*) AS answers,
       round(avg((a.result = 'correct')::int)::numeric, 2) AS share_correct,
       round(avg(a.response_time_ms)) AS avg_response_ms,
       max(a.attempt_number) AS max_attempt
  FROM core.answer a
  JOIN core.task t ON t.id = a.task_id
  JOIN core.exercise e ON e.id = t.exercise_id
  LEFT JOIN core.topic tp ON tp.id = e.topic_id
 WHERE a.learning_link_id = (SELECT ll.id FROM core.learning_link ll
                               JOIN core.app_user lu ON lu.id = ll.learner_user_id
                               JOIN core.app_user tu ON tu.id = ll.teacher_user_id
                              WHERE lu.email = 'ben.learner@example.com' AND tu.email = 'anna.teacher@example.com' AND ll.ended_at IS NULL)
   AND a.answered_at >= TIMESTAMPTZ '2026-09-01'
 GROUP BY tp.name
 ORDER BY answers DESC;
-- Result on the test data: 2 rows.

-- Q07. Epic 4, adaptation proposal: what the system proposed and why.
SELECT ap.generated_at, ap.status, api.item_kind, e.instruction_text, rt.name AS because_of_topic,
       api.rationale_period_from, api.rationale_period_to, api.added_by, api.is_accepted
  FROM core.adaptation_proposal ap
  JOIN core.adaptation_proposal_item api ON api.adaptation_proposal_id = ap.id
  LEFT JOIN core.exercise e ON e.id = api.exercise_id
  LEFT JOIN core.topic rt ON rt.id = api.rationale_topic_id
 ORDER BY ap.generated_at, api.id;
-- Result on the test data: 5 rows.

-- Q08. Epic 5, homework of a learner: what is assigned and not yet completed, in order.
-- A homework consists of whole exercises and of separate tasks, so both lists are read.
SELECT h.due_at, x.sort_order, x.item_kind, x.what, ha.personal_note
  FROM core.homework_assignment ha
  JOIN core.homework h ON h.id = ha.homework_id
  JOIN core.learning_link ll ON ll.id = ha.learning_link_id
  JOIN core.app_user lu ON lu.id = ll.learner_user_id
  JOIN LATERAL (SELECT he.sort_order, he.item_kind, 'exercise: ' || e.instruction_text AS what
                  FROM core.homework_exercise he JOIN core.exercise e ON e.id = he.exercise_id
                 WHERE he.homework_id = h.id
                UNION ALL
                SELECT ht.sort_order, ht.item_kind, 'task: ' || t.task_text
                  FROM core.homework_task ht JOIN core.task t ON t.id = ht.task_id
                 WHERE ht.homework_id = h.id) x ON true
 WHERE lu.email = 'ben.learner@example.com' AND ha.completed_at IS NULL
 ORDER BY h.due_at, x.sort_order;
-- Result on the test data: 2 rows.

-- Q09. Epic 6, one queue for the day with a limit: what a learner revises on a given day.
-- The application reads the same rows through core.v_revision_queue, which takes the current day
-- of the learner; here the day is written out so that the result does not depend on when the query is run.
SELECT rr.next_revision_date, e.instruction_text, t.number_in_exercise, rr.part_id, rr.current_interval_days, rr.ease
  FROM core.revision_record rr
  JOIN core.learning_link ll ON ll.id = rr.learning_link_id
  JOIN core.app_user lu ON lu.id = ll.learner_user_id
  JOIN core.task t ON t.id = rr.task_id
  JOIN core.exercise e ON e.id = t.exercise_id
 WHERE lu.email = 'ben.learner@example.com'
   AND rr.next_revision_date <= DATE '2026-11-17'
   AND (rr.deferral_end_date IS NULL OR rr.deferral_end_date < DATE '2026-11-17')
 ORDER BY rr.next_revision_date, rr.ease
 LIMIT (SELECT daily_task_limit FROM core.app_user WHERE email = 'ben.learner@example.com');
-- Result on the test data: 2 rows.

-- Q10. Epic 6, tasks with errors come back more often: the latest answer to every task of a link.
SELECT task_id, result, attempt_number, answered_at
  FROM (SELECT a.task_id, a.result, a.attempt_number, a.answered_at,
               row_number() OVER (PARTITION BY a.task_id ORDER BY a.answered_at DESC) AS rn
          FROM core.answer a
         WHERE a.learning_link_id = (SELECT ll.id FROM core.learning_link ll
                                       JOIN core.app_user lu ON lu.id = ll.learner_user_id
                                       JOIN core.app_user tu ON tu.id = ll.teacher_user_id
                                      WHERE lu.email = 'ben.learner@example.com' AND tu.email = 'anna.teacher@example.com' AND ll.ended_at IS NULL)) x
 WHERE rn = 1
 ORDER BY answered_at DESC;
-- Result on the test data: 7 rows.

-- Q11. Epic 7, correctness counts, not speed: result of a competition without the practice tasks.
SELECT cp.nickname, cp.team_number,
       count(*) FILTER (WHERE x.rn > c.practice_task_count) AS scored_answers,
       count(*) FILTER (WHERE x.rn > c.practice_task_count AND x.result = 'correct') AS correct
  FROM core.competition c
  JOIN core.competition_participation cp ON cp.competition_id = c.id
  LEFT JOIN (SELECT a.competition_participation_id, a.result,
                    row_number() OVER (PARTITION BY a.competition_participation_id ORDER BY a.answered_at) AS rn
               FROM core.answer a WHERE a.competition_participation_id IS NOT NULL) x
         ON x.competition_participation_id = cp.id
 GROUP BY c.id, cp.id, cp.nickname, cp.team_number
 ORDER BY c.id, correct DESC, cp.nickname;
-- Result on the test data: 3 rows.

-- Q12. Epic 1, anonymous statistics: share of correct answers by exercise type and level for a period.
SELECT et.code AS exercise_type, cl.name AS level, se.time_bucket,
       count(*) AS events, round(avg(se.is_correct::int)::numeric, 2) AS share_correct
  FROM stats.statistics_event se
  JOIN core.exercise_type et ON et.id = se.exercise_type_id
  JOIN core.cefr_level cl ON cl.id = se.cefr_level_id
 WHERE se.event_date BETWEEN DATE '2026-09-01' AND DATE '2026-11-30'
 GROUP BY et.code, cl.name, cl.sort_order, se.time_bucket
 ORDER BY et.code, cl.sort_order, se.time_bucket;
-- Result on the test data: 3 rows.

-- Q13. Epic 2, transcription and audio: target words of a task in the variant the learner has chosen.
SELECT w.spelling, w.explanation, pv.code AS variant, wp.transcription, wp.audio_location
  FROM core.exercise_target_word etw
  JOIN core.word w ON w.id = etw.word_id
  JOIN core.app_user lu ON lu.email = 'carla.learner@example.com'
  LEFT JOIN core.pronunciation_choice pc ON pc.learner_user_id = lu.id AND pc.language_id = w.language_id
  LEFT JOIN core.pronunciation_variant pv ON pv.id = pc.pronunciation_variant_id
  LEFT JOIN core.word_pronunciation wp ON wp.word_id = w.id AND wp.pronunciation_variant_id = pc.pronunciation_variant_id
 ORDER BY w.spelling;
-- Result on the test data: 3 rows.

-- Q14. Epic 2, change the exercise type: types the gap-fill with a bank can be turned into, harder ones marked.
SELECT tt.code AS target_type, tt.display_mode, c.is_harder
  FROM core.exercise_type_compatibility c
  JOIN core.exercise_type st ON st.id = c.source_type_id
  JOIN core.exercise_type tt ON tt.id = c.target_type_id
 WHERE st.code = 'gap_bank'
 ORDER BY c.is_harder, tt.code;
-- Result on the test data: 2 rows.
