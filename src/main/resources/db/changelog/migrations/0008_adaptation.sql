--liquibase formatted sql

--changeset samitava:0008-adaptation-proposal
CREATE TABLE core.adaptation_proposal (
    id               bigint      GENERATED ALWAYS AS IDENTITY,
    learning_link_id bigint      NOT NULL,
    generated_at     timestamptz NOT NULL,
    status           text        NOT NULL,
    decided_by       text,
    decided_at       timestamptz,
    CONSTRAINT pk_adaptation_proposal PRIMARY KEY (id),
    CONSTRAINT ck_adaptation_proposal__status CHECK (
        status IN ('proposed', 'approved', 'modified', 'assigned')
    ),
    CONSTRAINT ck_adaptation_proposal__decided_by CHECK (decided_by IN ('system', 'user')),
    CONSTRAINT ck_adaptation_proposal__decision_complete CHECK (
        (decided_by IS NULL) = (decided_at IS NULL)
    ),
    CONSTRAINT ck_adaptation_proposal__status_matches_decision CHECK (
        (status = 'proposed') = (decided_by IS NULL)
    ),
    CONSTRAINT fk_adaptation_proposal__learning_link FOREIGN KEY (learning_link_id)
        REFERENCES core.learning_link (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.adaptation_proposal IS 'Proposal of what to do next for a learner. Nothing is assigned until a decision is made.';
COMMENT ON COLUMN core.adaptation_proposal.id IS 'Surrogate key.';
COMMENT ON COLUMN core.adaptation_proposal.learning_link_id IS 'Learning link the proposal is built for.';
COMMENT ON COLUMN core.adaptation_proposal.generated_at IS 'Moment the proposal was generated.';
COMMENT ON COLUMN core.adaptation_proposal.status IS 'Status: proposed, approved, modified or assigned.';
COMMENT ON COLUMN core.adaptation_proposal.decided_by IS 'Who made the decision: system or user. NULL until a decision is made.';
COMMENT ON COLUMN core.adaptation_proposal.decided_at IS 'Moment of the decision. NULL until a decision is made.';
--rollback DROP TABLE core.adaptation_proposal;

--changeset samitava:0008-adaptation-proposal-item
CREATE TABLE core.adaptation_proposal_item (
    id                        bigint  GENERATED ALWAYS AS IDENTITY,
    adaptation_proposal_id    bigint  NOT NULL,
    item_kind                 text    NOT NULL,
    exercise_id               bigint  NOT NULL,
    rationale_topic_id        bigint,
    rationale_period_from     date,
    rationale_period_to       date,
    added_by                  text    NOT NULL,
    is_accepted               boolean NOT NULL DEFAULT true,
    shown_as_exercise_type_id bigint,
    CONSTRAINT pk_adaptation_proposal_item PRIMARY KEY (id),
    CONSTRAINT uq_adaptation_proposal_item__pair UNIQUE (adaptation_proposal_id, exercise_id),
    CONSTRAINT ck_adaptation_proposal_item__item_kind CHECK (
        item_kind IN ('give_next', 'return_to_revision', 'make_easier', 'make_harder')
    ),
    CONSTRAINT ck_adaptation_proposal_item__added_by CHECK (added_by IN ('system', 'user')),
    CONSTRAINT ck_adaptation_proposal_item__period CHECK (
        (rationale_period_from IS NULL AND rationale_period_to IS NULL)
        OR (rationale_period_from <= rationale_period_to)
    ),
    CONSTRAINT ck_adaptation_proposal_item__system_has_rationale CHECK (
        added_by <> 'system' OR rationale_period_from IS NOT NULL
    ),
    CONSTRAINT ck_adaptation_proposal_item__shown_type_only_for_change CHECK (
        shown_as_exercise_type_id IS NULL OR item_kind IN ('make_easier', 'make_harder')
    ),
    CONSTRAINT fk_adaptation_proposal_item__adaptation_proposal FOREIGN KEY (adaptation_proposal_id)
        REFERENCES core.adaptation_proposal (id) ON DELETE CASCADE,
    CONSTRAINT fk_adaptation_proposal_item__exercise FOREIGN KEY (exercise_id)
        REFERENCES core.exercise (id) ON DELETE CASCADE,
    CONSTRAINT fk_adaptation_proposal_item__rationale_topic FOREIGN KEY (rationale_topic_id)
        REFERENCES core.topic (id) ON DELETE SET NULL,
    CONSTRAINT fk_adaptation_proposal_item__shown_as_exercise_type FOREIGN KEY (shown_as_exercise_type_id)
        REFERENCES core.exercise_type (id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.adaptation_proposal_item IS 'One item of an adaptation proposal: an exercise and what to do with it.';
COMMENT ON COLUMN core.adaptation_proposal_item.id IS 'Surrogate key.';
COMMENT ON COLUMN core.adaptation_proposal_item.adaptation_proposal_id IS 'Proposal the item belongs to.';
COMMENT ON COLUMN core.adaptation_proposal_item.item_kind IS 'Kind: give_next, return_to_revision, make_easier or make_harder.';
COMMENT ON COLUMN core.adaptation_proposal_item.exercise_id IS 'Exercise the item is about.';
COMMENT ON COLUMN core.adaptation_proposal_item.rationale_topic_id IS 'Topic the rationale is based on. NULL for an item added by a user.';
COMMENT ON COLUMN core.adaptation_proposal_item.rationale_period_from IS 'Start of the period the rationale is based on. NULL for an item added by a user.';
COMMENT ON COLUMN core.adaptation_proposal_item.rationale_period_to IS 'End of the period the rationale is based on. NULL for an item added by a user.';
COMMENT ON COLUMN core.adaptation_proposal_item.added_by IS 'Who added the item: system or user.';
COMMENT ON COLUMN core.adaptation_proposal_item.is_accepted IS 'False when the user rejected the item. A rejected item stays in the record but is not given to the learner.';
COMMENT ON COLUMN core.adaptation_proposal_item.shown_as_exercise_type_id IS 'Exercise type the exercise is shown in. Filled only for make_easier and make_harder.';
--rollback DROP TABLE core.adaptation_proposal_item;

--changeset samitava:0008-homework-adaptation-proposal-fk
ALTER TABLE core.homework
    ADD CONSTRAINT fk_homework__adaptation_proposal FOREIGN KEY (adaptation_proposal_id)
        REFERENCES core.adaptation_proposal (id) ON DELETE SET NULL;
--rollback ALTER TABLE core.homework DROP CONSTRAINT fk_homework__adaptation_proposal;
