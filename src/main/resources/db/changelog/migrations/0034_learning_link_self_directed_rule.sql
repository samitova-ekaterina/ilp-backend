--liquibase formatted sql

--changeset samitava:0034-one-open-self-directed-link-per-language
-- A self-directed learner has one course per language. uq_learning_link__open_triple does not cover this:
-- the teacher is NULL in a self-directed link, and NULLs never collide in a unique index.
CREATE UNIQUE INDEX uq_learning_link__open_self_directed
    ON core.learning_link (learner_user_id, study_language_id)
    WHERE link_kind = 'self_directed' AND ended_at IS NULL;
--rollback DROP INDEX core.uq_learning_link__open_self_directed;
