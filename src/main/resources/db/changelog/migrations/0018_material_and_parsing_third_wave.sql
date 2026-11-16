--liquibase formatted sql

--changeset samitava:0018-presentation-item
CREATE TABLE core.presentation_item (
    id            bigint      GENERATED ALWAYS AS IDENTITY,
    exercise_id   bigint,
    task_id       bigint,
    item_kind     text        NOT NULL,
    content       text,
    file_location text,
    generated_at  timestamptz NOT NULL,
    confirmed_at  timestamptz,
    CONSTRAINT pk_presentation_item PRIMARY KEY (id),
    CONSTRAINT ck_presentation_item__one_target CHECK (num_nonnulls(exercise_id, task_id) = 1),
    CONSTRAINT ck_presentation_item__item_kind CHECK (item_kind IN ('illustration', 'hint', 'glossary')),
    CONSTRAINT ck_presentation_item__content_matches_kind CHECK (
        (item_kind = 'illustration' AND file_location IS NOT NULL AND content IS NULL)
        OR (item_kind IN ('hint', 'glossary') AND content IS NOT NULL AND file_location IS NULL)
    ),
    CONSTRAINT fk_presentation_item__exercise FOREIGN KEY (exercise_id)
        REFERENCES core.exercise (id) ON DELETE CASCADE,
    CONSTRAINT fk_presentation_item__task FOREIGN KEY (task_id)
        REFERENCES core.task (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.presentation_item IS 'Presentation element added to an exercise or a task on request: illustration, hint or glossary. It never changes the content of tasks and keys.';
COMMENT ON COLUMN core.presentation_item.id IS 'Surrogate key.';
COMMENT ON COLUMN core.presentation_item.exercise_id IS 'Exercise the element belongs to. Exactly one of exercise_id and task_id is filled.';
COMMENT ON COLUMN core.presentation_item.task_id IS 'Task the element belongs to. Exactly one of exercise_id and task_id is filled.';
COMMENT ON COLUMN core.presentation_item.item_kind IS 'Kind: illustration, hint or glossary.';
COMMENT ON COLUMN core.presentation_item.content IS 'Text of the hint or glossary. NULL for an illustration.';
COMMENT ON COLUMN core.presentation_item.file_location IS 'Address of the file. Filled only for an illustration.';
COMMENT ON COLUMN core.presentation_item.generated_at IS 'Moment the element was generated.';
COMMENT ON COLUMN core.presentation_item.confirmed_at IS 'Moment the author confirmed the element. NULL while it is pending; until then it is not shown to learners.';
--rollback DROP TABLE core.presentation_item;

--changeset samitava:0018-word
CREATE TABLE core.word (
    id                     bigint GENERATED ALWAYS AS IDENTITY,
    language_id            bigint NOT NULL,
    spelling               text   NOT NULL,
    transcription          text,
    explanation            text,
    reference_requested_at timestamptz,
    audio_location         text,
    audio_requested_at     timestamptz,
    CONSTRAINT pk_word PRIMARY KEY (id),
    CONSTRAINT uq_word__language_spelling UNIQUE (language_id, spelling),
    CONSTRAINT fk_word__language FOREIGN KEY (language_id)
        REFERENCES core.language (id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.word IS 'Word with reference data obtained from external dictionaries and speech synthesis. A result is stored so that a paid service is not asked twice.';
COMMENT ON COLUMN core.word.id IS 'Surrogate key.';
COMMENT ON COLUMN core.word.language_id IS 'Language of the word.';
COMMENT ON COLUMN core.word.spelling IS 'Spelling of the word.';
COMMENT ON COLUMN core.word.transcription IS 'Transcription from a dictionary. NULL when the dictionary has no exact match.';
COMMENT ON COLUMN core.word.explanation IS 'Explanation from a dictionary. NULL when the dictionary has no exact match.';
COMMENT ON COLUMN core.word.reference_requested_at IS 'Moment the reference data was requested. NULL when it was never requested. A date with empty reference data means the word was not found.';
COMMENT ON COLUMN core.word.audio_location IS 'Address of the audio file. NULL until the audio exists.';
COMMENT ON COLUMN core.word.audio_requested_at IS 'Moment the audio was requested. NULL when it was never requested.';
--rollback DROP TABLE core.word;

--changeset samitava:0018-task-target-word
CREATE TABLE core.task_target_word (
    task_id bigint NOT NULL,
    word_id bigint NOT NULL,
    CONSTRAINT pk_task_target_word PRIMARY KEY (task_id, word_id),
    CONSTRAINT fk_task_target_word__task FOREIGN KEY (task_id)
        REFERENCES core.task (id) ON DELETE CASCADE,
    CONSTRAINT fk_task_target_word__word FOREIGN KEY (word_id)
        REFERENCES core.word (id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.task_target_word IS 'Target word of a single task. Words of a shared word bank are stored in exercise_target_word.';
COMMENT ON COLUMN core.task_target_word.task_id IS 'Task.';
COMMENT ON COLUMN core.task_target_word.word_id IS 'Target word.';
--rollback DROP TABLE core.task_target_word;

--changeset samitava:0018-exercise-target-word
CREATE TABLE core.exercise_target_word (
    exercise_id bigint NOT NULL,
    word_id     bigint NOT NULL,
    CONSTRAINT pk_exercise_target_word PRIMARY KEY (exercise_id, word_id),
    CONSTRAINT fk_exercise_target_word__exercise FOREIGN KEY (exercise_id)
        REFERENCES core.exercise (id) ON DELETE CASCADE,
    CONSTRAINT fk_exercise_target_word__word FOREIGN KEY (word_id)
        REFERENCES core.word (id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.exercise_target_word IS 'Target word of the shared word bank of an exercise, stored once for the whole exercise.';
COMMENT ON COLUMN core.exercise_target_word.exercise_id IS 'Exercise.';
COMMENT ON COLUMN core.exercise_target_word.word_id IS 'Target word.';
--rollback DROP TABLE core.exercise_target_word;

--changeset samitava:0018-task-text-audio
ALTER TABLE core.task
    ADD COLUMN text_audio_location text;
COMMENT ON COLUMN core.task.text_audio_location IS 'Address of the audio file with the task text. NULL until the audio is requested.';
--rollback ALTER TABLE core.task DROP COLUMN text_audio_location;

--changeset samitava:0018-image-kind-and-source
ALTER TABLE core.image
    ADD COLUMN image_kind      text NOT NULL,
    ADD COLUMN source_image_id bigint,
    ADD COLUMN confirmed_at    timestamptz,
    ADD CONSTRAINT ck_image__image_kind CHECK (image_kind IN ('ordinary', 'grid', 'diagram')),
    ADD CONSTRAINT ck_image__origin_matches_source CHECK (
        (origin = 'redrawn' AND source_image_id IS NOT NULL)
        OR (origin = 'source' AND source_image_id IS NULL)
    ),
    ADD CONSTRAINT fk_image__source_image FOREIGN KEY (source_image_id)
        REFERENCES core.image (id) ON DELETE CASCADE;
COMMENT ON COLUMN core.image.image_kind IS 'Kind: ordinary, grid or diagram. Redrawing is not offered for a grid or a diagram.';
COMMENT ON COLUMN core.image.source_image_id IS 'Image this one was redrawn from. Filled only for a redrawn image.';
COMMENT ON COLUMN core.image.confirmed_at IS 'Moment the author confirmed the redrawn image. NULL while it waits for the decision; always NULL for a source image.';
--rollback ALTER TABLE core.image DROP COLUMN confirmed_at, DROP COLUMN source_image_id, DROP COLUMN image_kind;
