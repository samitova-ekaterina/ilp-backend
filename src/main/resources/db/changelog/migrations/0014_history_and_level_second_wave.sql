--liquibase formatted sql

--changeset samitava:0014-level-change
CREATE TABLE core.level_change (
    id                     bigint      GENERATED ALWAYS AS IDENTITY,
    scale_level_id         bigint      NOT NULL,
    previous_level_step_id bigint      NOT NULL,
    new_level_step_id      bigint      NOT NULL,
    changed_at             timestamptz NOT NULL,
    changed_by             text        NOT NULL,
    shown_to_learner_at    timestamptz,
    CONSTRAINT pk_level_change PRIMARY KEY (id),
    CONSTRAINT ck_level_change__steps_differ CHECK (new_level_step_id <> previous_level_step_id),
    CONSTRAINT ck_level_change__changed_by CHECK (changed_by IN ('system', 'user')),
    CONSTRAINT fk_level_change__scale_level FOREIGN KEY (scale_level_id)
        REFERENCES core.scale_level (id) ON DELETE CASCADE,
    CONSTRAINT fk_level_change__previous_level_step FOREIGN KEY (previous_level_step_id)
        REFERENCES core.level_step (id) ON DELETE RESTRICT,
    CONSTRAINT fk_level_change__new_level_step FOREIGN KEY (new_level_step_id)
        REFERENCES core.level_step (id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.level_change IS 'Journal of level changes on a scale. A row is written once and is not changed afterwards, except for the moment it was shown to the learner.';
COMMENT ON COLUMN core.level_change.id IS 'Surrogate key.';
COMMENT ON COLUMN core.level_change.scale_level_id IS 'Level on a scale that changed. Identifies both the learning link and the scale.';
COMMENT ON COLUMN core.level_change.previous_level_step_id IS 'Step before the change.';
COMMENT ON COLUMN core.level_change.new_level_step_id IS 'Step after the change. Differs from the previous step.';
COMMENT ON COLUMN core.level_change.changed_at IS 'Moment of the change.';
COMMENT ON COLUMN core.level_change.changed_by IS 'Who made the change: system or user. Not a reference to a user.';
COMMENT ON COLUMN core.level_change.shown_to_learner_at IS 'Moment the congratulation was shown to the learner. NULL until it is shown.';
--rollback DROP TABLE core.level_change;

--changeset samitava:0014-oral-error-type
ALTER TABLE core.oral_error
    ADD COLUMN error_type_id bigint,
    ADD CONSTRAINT fk_oral_error__error_type FOREIGN KEY (error_type_id)
        REFERENCES core.error_type (id) ON DELETE RESTRICT;
COMMENT ON COLUMN core.oral_error.error_type_id IS 'Type of the mistake. NULL until it is specified.';
--rollback ALTER TABLE core.oral_error DROP COLUMN error_type_id;
