--liquibase formatted sql

--changeset samitava:0010-error-type
CREATE TABLE core.error_type (
    id   bigint GENERATED ALWAYS AS IDENTITY,
    code text   NOT NULL,
    name text   NOT NULL,
    CONSTRAINT pk_error_type PRIMARY KEY (id),
    CONSTRAINT uq_error_type__code UNIQUE (code),
    CONSTRAINT uq_error_type__name UNIQUE (name)
);
COMMENT ON TABLE core.error_type IS 'Kind of mistake in a learner answer: spelling, form, word choice, comprehension.';
COMMENT ON COLUMN core.error_type.id IS 'Surrogate key.';
COMMENT ON COLUMN core.error_type.code IS 'Stable identifier used by the application. Never changed or translated.';
COMMENT ON COLUMN core.error_type.name IS 'Type name shown to users.';
--rollback DROP TABLE core.error_type;
