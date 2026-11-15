--liquibase formatted sql

--changeset samitava:0002-scale
CREATE TABLE core.scale (
    id            bigint  GENERATED ALWAYS AS IDENTITY,
    code          text    NOT NULL,
    name          text    NOT NULL,
    display_order integer NOT NULL,
    CONSTRAINT pk_scale PRIMARY KEY (id),
    CONSTRAINT uq_scale__code UNIQUE (code),
    CONSTRAINT uq_scale__name UNIQUE (name),
    CONSTRAINT uq_scale__display_order UNIQUE (display_order)
);
COMMENT ON TABLE core.scale IS 'Skill scale on which a learner level is measured: vocabulary, grammar, writing, speech.';
COMMENT ON COLUMN core.scale.id IS 'Surrogate key.';
COMMENT ON COLUMN core.scale.code IS 'Stable identifier used by the application. Never changed or translated.';
COMMENT ON COLUMN core.scale.name IS 'Scale name shown to users.';
COMMENT ON COLUMN core.scale.display_order IS 'Position of the scale in the level chart. The order is always the same.';
--rollback DROP TABLE core.scale;

--changeset samitava:0002-cefr-level
CREATE TABLE core.cefr_level (
    id         bigint  GENERATED ALWAYS AS IDENTITY,
    name       text    NOT NULL,
    sort_order integer NOT NULL,
    CONSTRAINT pk_cefr_level PRIMARY KEY (id),
    CONSTRAINT uq_cefr_level__name UNIQUE (name),
    CONSTRAINT uq_cefr_level__sort_order UNIQUE (sort_order)
);
COMMENT ON TABLE core.cefr_level IS 'CEFR level: A1, A2, B1 and so on.';
COMMENT ON COLUMN core.cefr_level.id IS 'Surrogate key.';
COMMENT ON COLUMN core.cefr_level.name IS 'CEFR mark, for example A1.';
COMMENT ON COLUMN core.cefr_level.sort_order IS 'Ordinal number used to compare levels: higher or lower.';
--rollback DROP TABLE core.cefr_level;

--changeset samitava:0002-level-step
CREATE TABLE core.level_step (
    id            bigint  GENERATED ALWAYS AS IDENTITY,
    name          text    NOT NULL,
    sort_order    integer NOT NULL,
    cefr_level_id bigint  NOT NULL,
    CONSTRAINT pk_level_step PRIMARY KEY (id),
    CONSTRAINT uq_level_step__name UNIQUE (name),
    CONSTRAINT uq_level_step__sort_order UNIQUE (sort_order),
    CONSTRAINT fk_level_step__cefr_level FOREIGN KEY (cefr_level_id)
        REFERENCES core.cefr_level (id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.level_step IS 'Step inside a CEFR level. Levels are measured in steps finer than CEFR.';
COMMENT ON COLUMN core.level_step.id IS 'Surrogate key.';
COMMENT ON COLUMN core.level_step.name IS 'Step name.';
COMMENT ON COLUMN core.level_step.sort_order IS 'Ordinal number across all steps. Defines the next step.';
COMMENT ON COLUMN core.level_step.cefr_level_id IS 'CEFR level the step belongs to.';
--rollback DROP TABLE core.level_step;

--changeset samitava:0002-exercise-type
CREATE TABLE core.exercise_type (
    id                         bigint  GENERATED ALWAYS AS IDENTITY,
    code                       text    NOT NULL,
    name                       text    NOT NULL,
    recognition_features       jsonb   NOT NULL,
    display_mode               text    NOT NULL,
    checking_mode              text    NOT NULL,
    reference_response_time_ms integer,
    body_schema                jsonb   NOT NULL,
    CONSTRAINT pk_exercise_type PRIMARY KEY (id),
    CONSTRAINT uq_exercise_type__code UNIQUE (code),
    CONSTRAINT uq_exercise_type__name UNIQUE (name),
    CONSTRAINT ck_exercise_type__checking_mode CHECK (checking_mode IN ('automatic', 'reviewer')),
    CONSTRAINT ck_exercise_type__reference_time_positive CHECK (reference_response_time_ms > 0)
);
COMMENT ON TABLE core.exercise_type IS 'Catalogue of exercise types. New types are added as data, without schema changes.';
COMMENT ON COLUMN core.exercise_type.id IS 'Surrogate key.';
COMMENT ON COLUMN core.exercise_type.code IS 'Stable identifier used by the application. Never changed or translated.';
COMMENT ON COLUMN core.exercise_type.name IS 'Type name shown to users.';
COMMENT ON COLUMN core.exercise_type.recognition_features IS 'Features by which the parser recognises the type in a document. Structure is described in the type catalogue.';
COMMENT ON COLUMN core.exercise_type.display_mode IS 'How an exercise of this type is shown to the learner.';
COMMENT ON COLUMN core.exercise_type.checking_mode IS 'How an answer is checked: automatic or reviewer.';
COMMENT ON COLUMN core.exercise_type.reference_response_time_ms IS 'Reference response time in milliseconds. NULL when no reference is set for the type.';
COMMENT ON COLUMN core.exercise_type.body_schema IS 'Description of the task body structure for this type. Task bodies are validated against it.';
--rollback DROP TABLE core.exercise_type;

--changeset samitava:0002-exercise-type-compatibility
CREATE TABLE core.exercise_type_compatibility (
    id             bigint  GENERATED ALWAYS AS IDENTITY,
    source_type_id bigint  NOT NULL,
    target_type_id bigint  NOT NULL,
    is_harder      boolean NOT NULL,
    CONSTRAINT pk_exercise_type_compatibility PRIMARY KEY (id),
    CONSTRAINT uq_exercise_type_compatibility__pair UNIQUE (source_type_id, target_type_id),
    CONSTRAINT ck_exercise_type_compatibility__different_types CHECK (source_type_id <> target_type_id),
    CONSTRAINT fk_exercise_type_compatibility__source_type FOREIGN KEY (source_type_id)
        REFERENCES core.exercise_type (id) ON DELETE CASCADE,
    CONSTRAINT fk_exercise_type_compatibility__target_type FOREIGN KEY (target_type_id)
        REFERENCES core.exercise_type (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.exercise_type_compatibility IS 'Which exercise type can be converted into which other type.';
COMMENT ON COLUMN core.exercise_type_compatibility.id IS 'Surrogate key.';
COMMENT ON COLUMN core.exercise_type_compatibility.source_type_id IS 'Type the exercise has.';
COMMENT ON COLUMN core.exercise_type_compatibility.target_type_id IS 'Type the exercise can be converted into.';
COMMENT ON COLUMN core.exercise_type_compatibility.is_harder IS 'True when the target type is harder than the source type.';
--rollback DROP TABLE core.exercise_type_compatibility;

--changeset samitava:0002-flag-reason
CREATE TABLE core.flag_reason (
    id   bigint GENERATED ALWAYS AS IDENTITY,
    code text   NOT NULL,
    name text   NOT NULL,
    CONSTRAINT pk_flag_reason PRIMARY KEY (id),
    CONSTRAINT uq_flag_reason__code UNIQUE (code),
    CONSTRAINT uq_flag_reason__name UNIQUE (name)
);
COMMENT ON TABLE core.flag_reason IS 'Reason why a place in parsed material is flagged for the author to confirm.';
COMMENT ON COLUMN core.flag_reason.id IS 'Surrogate key.';
COMMENT ON COLUMN core.flag_reason.code IS 'Stable identifier used by the application. Never changed or translated.';
COMMENT ON COLUMN core.flag_reason.name IS 'Reason shown to the author next to the flagged place.';
--rollback DROP TABLE core.flag_reason;

--changeset samitava:0002-policy-version
CREATE TABLE core.policy_version (
    id             bigint GENERATED ALWAYS AS IDENTITY,
    version_number text   NOT NULL,
    effective_from date   NOT NULL,
    policy_text    text   NOT NULL,
    CONSTRAINT pk_policy_version PRIMARY KEY (id),
    CONSTRAINT uq_policy_version__version_number UNIQUE (version_number)
);
COMMENT ON TABLE core.policy_version IS 'Version of the data processing policy that users consent to.';
COMMENT ON COLUMN core.policy_version.id IS 'Surrogate key.';
COMMENT ON COLUMN core.policy_version.version_number IS 'Version number, for example 1.2.';
COMMENT ON COLUMN core.policy_version.effective_from IS 'Date from which the version is in force.';
COMMENT ON COLUMN core.policy_version.policy_text IS 'Full text of the version, so that it is clear what exactly a user consented to.';
--rollback DROP TABLE core.policy_version;

--changeset samitava:0002-language
CREATE TABLE core.language (
    id   bigint GENERATED ALWAYS AS IDENTITY,
    code text   NOT NULL,
    name text   NOT NULL,
    CONSTRAINT pk_language PRIMARY KEY (id),
    CONSTRAINT uq_language__code UNIQUE (code),
    CONSTRAINT uq_language__name UNIQUE (name),
    CONSTRAINT ck_language__code_format CHECK (code ~ '^[a-z]{2}$')
);
COMMENT ON TABLE core.language IS 'Language: studied language or interface language.';
COMMENT ON COLUMN core.language.id IS 'Surrogate key.';
COMMENT ON COLUMN core.language.code IS 'Two-letter language code, ISO 639-1, for example en. Never changed or translated.';
COMMENT ON COLUMN core.language.name IS 'Language name shown to users.';
--rollback DROP TABLE core.language;
