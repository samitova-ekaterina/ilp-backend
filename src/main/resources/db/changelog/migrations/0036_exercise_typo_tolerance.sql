--liquibase formatted sql

--changeset samitava:0036-exercise-typo-tolerance
-- Strict by default: a tolerated typo must be a decision of the author, not an accident.
ALTER TABLE core.exercise ADD COLUMN is_typo_tolerated boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN core.exercise.is_typo_tolerated IS 'Whether a typed answer with a typo is accepted. Set by the author of the material.';
--rollback ALTER TABLE core.exercise DROP COLUMN is_typo_tolerated;
