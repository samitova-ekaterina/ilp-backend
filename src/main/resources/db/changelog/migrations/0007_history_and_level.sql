--liquibase formatted sql

--changeset samitava:0007-scale-level
CREATE TABLE core.scale_level (
    id                    bigint GENERATED ALWAYS AS IDENTITY,
    learning_link_id      bigint NOT NULL,
    scale_id              bigint NOT NULL,
    entry_level_step_id   bigint,
    current_level_step_id bigint,
    CONSTRAINT pk_scale_level PRIMARY KEY (id),
    CONSTRAINT uq_scale_level__pair UNIQUE (learning_link_id, scale_id),
    CONSTRAINT fk_scale_level__learning_link FOREIGN KEY (learning_link_id)
        REFERENCES core.learning_link (id) ON DELETE CASCADE,
    CONSTRAINT fk_scale_level__scale FOREIGN KEY (scale_id)
        REFERENCES core.scale (id) ON DELETE RESTRICT,
    CONSTRAINT fk_scale_level__entry_level_step FOREIGN KEY (entry_level_step_id)
        REFERENCES core.level_step (id) ON DELETE RESTRICT,
    CONSTRAINT fk_scale_level__current_level_step FOREIGN KEY (current_level_step_id)
        REFERENCES core.level_step (id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.scale_level IS 'Level of a learner on one scale within one learning link.';
COMMENT ON COLUMN core.scale_level.id IS 'Surrogate key.';
COMMENT ON COLUMN core.scale_level.learning_link_id IS 'Learning link the level belongs to.';
COMMENT ON COLUMN core.scale_level.scale_id IS 'Scale.';
COMMENT ON COLUMN core.scale_level.entry_level_step_id IS 'Step at the start of learning. NULL until set.';
COMMENT ON COLUMN core.scale_level.current_level_step_id IS 'Current step. NULL while there is no data; shown as no data.';
--rollback DROP TABLE core.scale_level;

--changeset samitava:0007-oral-error
CREATE TABLE core.oral_error (
    id               bigint      GENERATED ALWAYS AS IDENTITY,
    learning_link_id bigint      NOT NULL,
    lesson_id        bigint,
    task_id          bigint,
    topic_id         bigint,
    scale_id         bigint      NOT NULL,
    phrase           text,
    recorded_at      timestamptz NOT NULL,
    CONSTRAINT pk_oral_error PRIMARY KEY (id),
    CONSTRAINT fk_oral_error__learning_link FOREIGN KEY (learning_link_id)
        REFERENCES core.learning_link (id) ON DELETE CASCADE,
    CONSTRAINT fk_oral_error__lesson FOREIGN KEY (lesson_id)
        REFERENCES core.lesson (id) ON DELETE SET NULL,
    CONSTRAINT fk_oral_error__task FOREIGN KEY (task_id)
        REFERENCES core.task (id) ON DELETE SET NULL,
    CONSTRAINT fk_oral_error__topic FOREIGN KEY (topic_id)
        REFERENCES core.topic (id) ON DELETE SET NULL,
    CONSTRAINT fk_oral_error__scale FOREIGN KEY (scale_id)
        REFERENCES core.scale (id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.oral_error IS 'Oral error of a learner, recorded by the teacher during a lesson.';
COMMENT ON COLUMN core.oral_error.id IS 'Surrogate key.';
COMMENT ON COLUMN core.oral_error.learning_link_id IS 'Learning link of the learner.';
COMMENT ON COLUMN core.oral_error.lesson_id IS 'Lesson during which the error was recorded. Becomes NULL when the lesson is deleted.';
COMMENT ON COLUMN core.oral_error.task_id IS 'Task that was open at that moment. May be NULL.';
COMMENT ON COLUMN core.oral_error.topic_id IS 'Topic of the error. Taken from the current task; the teacher can change it.';
COMMENT ON COLUMN core.oral_error.scale_id IS 'Scale the error relates to. Speech by default.';
COMMENT ON COLUMN core.oral_error.phrase IS 'Word or phrase with the error. Optional; can be added after the lesson.';
COMMENT ON COLUMN core.oral_error.recorded_at IS 'Moment the error was recorded.';
--rollback DROP TABLE core.oral_error;

--changeset samitava:0007-note
CREATE TABLE core.note (
    id               bigint      GENERATED ALWAYS AS IDENTITY,
    learning_link_id bigint      NOT NULL,
    lesson_id        bigint,
    note_text        text        NOT NULL,
    written_at       timestamptz NOT NULL,
    CONSTRAINT pk_note PRIMARY KEY (id),
    CONSTRAINT fk_note__learning_link FOREIGN KEY (learning_link_id)
        REFERENCES core.learning_link (id) ON DELETE CASCADE,
    CONSTRAINT fk_note__lesson FOREIGN KEY (lesson_id)
        REFERENCES core.lesson (id) ON DELETE SET NULL
);
COMMENT ON TABLE core.note IS 'Note of a teacher about a learner.';
COMMENT ON COLUMN core.note.id IS 'Surrogate key.';
COMMENT ON COLUMN core.note.learning_link_id IS 'Learning link the note belongs to.';
COMMENT ON COLUMN core.note.lesson_id IS 'Lesson the note was written at. May be NULL.';
COMMENT ON COLUMN core.note.note_text IS 'Personal data. Free text about the learner.';
COMMENT ON COLUMN core.note.written_at IS 'Moment the note was written.';
--rollback DROP TABLE core.note;
