--liquibase formatted sql

--changeset samitava:0050-test-access-after-end context:test
-- A closed link whose teacher left the learner three months of access.
UPDATE core.learning_link ll
   SET access_until = (ll.ended_at AT TIME ZONE 'UTC')::date + 91
 WHERE ll.ended_at IS NOT NULL
   AND ll.link_kind = 'with_teacher'
   AND ll.learner_user_id = (SELECT id FROM core.app_user WHERE email = 'ben.learner@example.com')
   AND ll.teacher_user_id = (SELECT id FROM core.app_user WHERE email = 'eva.teacher@example.com');
--rollback UPDATE core.learning_link SET access_until = NULL WHERE access_until IS NOT NULL AND learner_user_id = (SELECT id FROM core.app_user WHERE email = 'ben.learner@example.com');
