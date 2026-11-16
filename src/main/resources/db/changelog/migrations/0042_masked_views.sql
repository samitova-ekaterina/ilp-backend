--liquibase formatted sql

--changeset samitava:0042-app-user-masked-view
-- The reading role has no access to e-mail and name in core.app_user. This view gives it enough
-- to recognise a record without disclosing the person.
CREATE VIEW core.v_app_user_masked WITH (security_barrier = true) AS
SELECT u.id,
       left(u.email, 1) || '***@' || split_part(u.email, '@', 2) AS email_masked,
       CASE WHEN u.display_name IS NULL THEN NULL ELSE left(u.display_name, 1) || '***' END AS display_name_masked,
       u.country_id,
       u.age_group,
       u.registration_role,
       u.interface_language_id,
       u.registered_at
  FROM core.app_user u;
COMMENT ON VIEW core.v_app_user_masked IS 'Users with masked personal data: the first character of the e-mail with its domain and the first character of the name.';
GRANT SELECT ON core.v_app_user_masked TO ilp_read;
--rollback DROP VIEW core.v_app_user_masked;

--changeset samitava:0042-note-masked-view
-- The text of a note is marked as personal data in the column comment but stayed readable for the reading role.
REVOKE SELECT ON core.note FROM ilp_read;
GRANT SELECT (id, learning_link_id, lesson_id, written_at) ON core.note TO ilp_read;
CREATE VIEW core.v_note_masked WITH (security_barrier = true) AS
SELECT n.id,
       n.learning_link_id,
       n.lesson_id,
       n.written_at,
       char_length(n.note_text) AS note_length
  FROM core.note n;
COMMENT ON VIEW core.v_note_masked IS 'Notes without their text: only the length of the text is shown.';
GRANT SELECT ON core.v_note_masked TO ilp_read;
--rollback DROP VIEW core.v_note_masked;
--rollback REVOKE SELECT (id, learning_link_id, lesson_id, written_at) ON core.note FROM ilp_read;
--rollback GRANT SELECT ON core.note TO ilp_read;
