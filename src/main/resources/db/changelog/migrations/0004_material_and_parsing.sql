--liquibase formatted sql

--changeset samitava:0004-material
CREATE TABLE core.material (
    id                bigint      GENERATED ALWAYS AS IDENTITY,
    owner_user_id     bigint      NOT NULL,
    name              text        NOT NULL,
    file_location     text        NOT NULL,
    file_size_bytes   integer     NOT NULL,
    page_count        integer     NOT NULL,
    has_text_layer    boolean     NOT NULL,
    cefr_level_id     bigint,
    study_language_id bigint      NOT NULL,
    processing_status text        NOT NULL,
    uploaded_at       timestamptz NOT NULL,
    course_id         bigint,
    CONSTRAINT pk_material PRIMARY KEY (id),
    CONSTRAINT ck_material__file_size_positive CHECK (file_size_bytes > 0),
    CONSTRAINT ck_material__page_count_positive CHECK (page_count > 0),
    CONSTRAINT ck_material__processing_status CHECK (
        processing_status IN ('processing', 'parsed', 'text_not_extracted', 'not_parsed')
    ),
    CONSTRAINT fk_material__owner_user FOREIGN KEY (owner_user_id)
        REFERENCES core.app_user (id) ON DELETE CASCADE,
    CONSTRAINT fk_material__cefr_level FOREIGN KEY (cefr_level_id)
        REFERENCES core.cefr_level (id) ON DELETE RESTRICT,
    CONSTRAINT fk_material__study_language FOREIGN KEY (study_language_id)
        REFERENCES core.language (id) ON DELETE RESTRICT,
    CONSTRAINT fk_material__course FOREIGN KEY (course_id)
        REFERENCES core.course (id) ON DELETE SET NULL
);
COMMENT ON TABLE core.material IS 'Uploaded PDF learning material. The file itself is stored outside the database.';
COMMENT ON COLUMN core.material.id IS 'Surrogate key.';
COMMENT ON COLUMN core.material.owner_user_id IS 'User who uploaded the material.';
COMMENT ON COLUMN core.material.name IS 'Material name. Used for search in the library.';
COMMENT ON COLUMN core.material.file_location IS 'Address of the file.';
COMMENT ON COLUMN core.material.file_size_bytes IS 'File size in bytes. The size limit is an application setting, not a database rule.';
COMMENT ON COLUMN core.material.page_count IS 'Number of pages. The page limit is an application setting.';
COMMENT ON COLUMN core.material.has_text_layer IS 'True when the PDF has a text layer.';
COMMENT ON COLUMN core.material.cefr_level_id IS 'Level of the material, set by the uploader. NULL until set.';
COMMENT ON COLUMN core.material.study_language_id IS 'Language the material teaches. Dictionaries and audio depend on it.';
COMMENT ON COLUMN core.material.processing_status IS 'Processing status: processing, parsed, text_not_extracted or not_parsed.';
COMMENT ON COLUMN core.material.uploaded_at IS 'Moment of upload.';
COMMENT ON COLUMN core.material.course_id IS 'Own course the material belongs to. NULL for a material of a teacher.';
--rollback DROP TABLE core.material;

--changeset samitava:0004-topic
CREATE TABLE core.topic (
    id            bigint GENERATED ALWAYS AS IDENTITY,
    name          text   NOT NULL,
    owner_user_id bigint,
    CONSTRAINT pk_topic PRIMARY KEY (id),
    CONSTRAINT uq_topic__owner_name UNIQUE (owner_user_id, name),
    CONSTRAINT fk_topic__owner_user FOREIGN KEY (owner_user_id)
        REFERENCES core.app_user (id) ON DELETE CASCADE
);
-- Catalogue topics have no owner, and the constraint above does not compare empty owners.
CREATE UNIQUE INDEX uq_topic__catalogue_name
    ON core.topic (name)
    WHERE owner_user_id IS NULL;
COMMENT ON TABLE core.topic IS 'Topic of exercises: from the common catalogue or created by a user.';
COMMENT ON COLUMN core.topic.id IS 'Surrogate key.';
COMMENT ON COLUMN core.topic.name IS 'Topic name. Unique for one owner and separately within the common catalogue.';
COMMENT ON COLUMN core.topic.owner_user_id IS 'User who created the topic. NULL for topics of the common catalogue.';
--rollback DROP TABLE core.topic;

--changeset samitava:0004-parsing-run
CREATE TABLE core.parsing_run (
    id          bigint      GENERATED ALWAYS AS IDENTITY,
    material_id bigint      NOT NULL,
    started_at  timestamptz NOT NULL,
    finished_at timestamptz,
    outcome     text,
    CONSTRAINT pk_parsing_run PRIMARY KEY (id),
    CONSTRAINT ck_parsing_run__finished_after_started CHECK (finished_at >= started_at),
    CONSTRAINT ck_parsing_run__outcome CHECK (outcome IN ('completed', 'timed_out', 'text_not_extracted')),
    CONSTRAINT fk_parsing_run__material FOREIGN KEY (material_id)
        REFERENCES core.material (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.parsing_run IS 'One run of parsing a material into exercises.';
COMMENT ON COLUMN core.parsing_run.id IS 'Surrogate key.';
COMMENT ON COLUMN core.parsing_run.material_id IS 'Material that was parsed.';
COMMENT ON COLUMN core.parsing_run.started_at IS 'Moment the run started.';
COMMENT ON COLUMN core.parsing_run.finished_at IS 'Moment the run finished. NULL while running. Distinguishes a running parse from a stalled one.';
COMMENT ON COLUMN core.parsing_run.outcome IS 'Outcome: completed, timed_out or text_not_extracted. NULL while running.';
--rollback DROP TABLE core.parsing_run;

--changeset samitava:0004-exercise
CREATE TABLE core.exercise (
    id                 bigint      GENERATED ALWAYS AS IDENTITY,
    parsing_run_id     bigint      NOT NULL,
    exercise_type_id   bigint,
    topic_id           bigint,
    status             text        NOT NULL,
    number_in_document text,
    instruction_text   text        NOT NULL,
    shared_body        jsonb,
    source_page        integer     NOT NULL,
    excluded_at        timestamptz,
    scale_id           bigint,
    CONSTRAINT pk_exercise PRIMARY KEY (id),
    CONSTRAINT ck_exercise__status CHECK (status IN ('draft', 'approved')),
    CONSTRAINT ck_exercise__source_page_positive CHECK (source_page > 0),
    CONSTRAINT ck_exercise__approved_has_scale CHECK (status <> 'approved' OR scale_id IS NOT NULL),
    CONSTRAINT fk_exercise__parsing_run FOREIGN KEY (parsing_run_id)
        REFERENCES core.parsing_run (id) ON DELETE CASCADE,
    CONSTRAINT fk_exercise__exercise_type FOREIGN KEY (exercise_type_id)
        REFERENCES core.exercise_type (id) ON DELETE RESTRICT,
    CONSTRAINT fk_exercise__topic FOREIGN KEY (topic_id)
        REFERENCES core.topic (id) ON DELETE RESTRICT,
    CONSTRAINT fk_exercise__scale FOREIGN KEY (scale_id)
        REFERENCES core.scale (id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.exercise IS 'Exercise extracted from a material. Consists of tasks.';
COMMENT ON COLUMN core.exercise.id IS 'Surrogate key.';
COMMENT ON COLUMN core.exercise.parsing_run_id IS 'Parsing run that produced the exercise. Through it the exercise knows its material.';
COMMENT ON COLUMN core.exercise.exercise_type_id IS 'Exercise type. NULL when the type was not recognised.';
COMMENT ON COLUMN core.exercise.topic_id IS 'Topic. NULL until assigned.';
COMMENT ON COLUMN core.exercise.status IS 'Status: draft or approved.';
COMMENT ON COLUMN core.exercise.number_in_document IS 'Number of the exercise in the document, for example 3a. Other exercises refer to it. NULL when the document gives no number.';
COMMENT ON COLUMN core.exercise.instruction_text IS 'Instruction common to all tasks of the exercise.';
COMMENT ON COLUMN core.exercise.shared_body IS 'Part of the body shared by the tasks, such as a word bank. NULL when there is none. Structure is described in the type catalogue.';
COMMENT ON COLUMN core.exercise.source_page IS 'Page of the document where the exercise is.';
COMMENT ON COLUMN core.exercise.excluded_at IS 'Moment the exercise was excluded. NULL while not excluded. Cleared on return; the status stays as it was.';
COMMENT ON COLUMN core.exercise.scale_id IS 'Scale the exercise trains. Must be filled before approval.';
--rollback DROP TABLE core.exercise;

--changeset samitava:0004-task
CREATE TABLE core.task (
    id                 bigint  GENERATED ALWAYS AS IDENTITY,
    exercise_id        bigint  NOT NULL,
    number_in_exercise integer NOT NULL,
    task_text          text    NOT NULL,
    body               jsonb   NOT NULL,
    source_page        integer NOT NULL,
    position_on_page   integer NOT NULL,
    CONSTRAINT pk_task PRIMARY KEY (id),
    CONSTRAINT uq_task__exercise_number UNIQUE (exercise_id, number_in_exercise),
    CONSTRAINT ck_task__number_positive CHECK (number_in_exercise > 0),
    CONSTRAINT ck_task__source_page_positive CHECK (source_page > 0),
    CONSTRAINT ck_task__position_positive CHECK (position_on_page > 0),
    CONSTRAINT fk_task__exercise FOREIGN KEY (exercise_id)
        REFERENCES core.exercise (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.task IS 'Single task of an exercise: the unit a learner answers.';
COMMENT ON COLUMN core.task.id IS 'Surrogate key.';
COMMENT ON COLUMN core.task.exercise_id IS 'Exercise the task belongs to.';
COMMENT ON COLUMN core.task.number_in_exercise IS 'Number of the task inside the exercise. The answer key is matched to the task by it.';
COMMENT ON COLUMN core.task.task_text IS 'Task text, character for character as in the document.';
COMMENT ON COLUMN core.task.body IS 'Task body: gaps, options, key answers, example flag, highlighted parts. Structure is described in the type catalogue.';
COMMENT ON COLUMN core.task.source_page IS 'Page of the document where the task is.';
COMMENT ON COLUMN core.task.position_on_page IS 'Ordinal position of the task on the page, from top to bottom.';
--rollback DROP TABLE core.task;

--changeset samitava:0004-exercise-dependency
CREATE TABLE core.exercise_dependency (
    id                       bigint GENERATED ALWAYS AS IDENTITY,
    dependent_exercise_id    bigint NOT NULL,
    prerequisite_exercise_id bigint NOT NULL,
    CONSTRAINT pk_exercise_dependency PRIMARY KEY (id),
    CONSTRAINT uq_exercise_dependency__pair UNIQUE (dependent_exercise_id, prerequisite_exercise_id),
    CONSTRAINT ck_exercise_dependency__different_exercises CHECK (dependent_exercise_id <> prerequisite_exercise_id),
    CONSTRAINT fk_exercise_dependency__dependent_exercise FOREIGN KEY (dependent_exercise_id)
        REFERENCES core.exercise (id) ON DELETE CASCADE,
    CONSTRAINT fk_exercise_dependency__prerequisite_exercise FOREIGN KEY (prerequisite_exercise_id)
        REFERENCES core.exercise (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.exercise_dependency IS 'Dependency between exercises: one exercise relies on another.';
COMMENT ON COLUMN core.exercise_dependency.id IS 'Surrogate key.';
COMMENT ON COLUMN core.exercise_dependency.dependent_exercise_id IS 'Exercise that depends on another one.';
COMMENT ON COLUMN core.exercise_dependency.prerequisite_exercise_id IS 'Exercise it depends on.';
--rollback DROP TABLE core.exercise_dependency;

--changeset samitava:0004-flag
CREATE TABLE core.flag (
    id             bigint GENERATED ALWAYS AS IDENTITY,
    task_id        bigint,
    exercise_id    bigint,
    place_in_task  text,
    flag_reason_id bigint NOT NULL,
    status         text   NOT NULL,
    original_value text,
    CONSTRAINT pk_flag PRIMARY KEY (id),
    CONSTRAINT ck_flag__one_target CHECK (num_nonnulls(task_id, exercise_id) = 1),
    CONSTRAINT ck_flag__status CHECK (status IN ('pending', 'confirmed', 'corrected')),
    CONSTRAINT fk_flag__task FOREIGN KEY (task_id)
        REFERENCES core.task (id) ON DELETE CASCADE,
    CONSTRAINT fk_flag__exercise FOREIGN KEY (exercise_id)
        REFERENCES core.exercise (id) ON DELETE CASCADE,
    CONSTRAINT fk_flag__flag_reason FOREIGN KEY (flag_reason_id)
        REFERENCES core.flag_reason (id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.flag IS 'Flag on a doubtful place of parsed material that the author must confirm or correct.';
COMMENT ON COLUMN core.flag.id IS 'Surrogate key.';
COMMENT ON COLUMN core.flag.task_id IS 'Flagged task. Exactly one of task_id and exercise_id is filled.';
COMMENT ON COLUMN core.flag.exercise_id IS 'Flagged exercise. Exactly one of task_id and exercise_id is filled.';
COMMENT ON COLUMN core.flag.place_in_task IS 'Flagged part of the task body: which gap or answer. NULL when the whole task is flagged.';
COMMENT ON COLUMN core.flag.flag_reason_id IS 'Reason of the flag.';
COMMENT ON COLUMN core.flag.status IS 'State: pending, confirmed or corrected.';
COMMENT ON COLUMN core.flag.original_value IS 'Value that stood in the document before the author corrected it. NULL until a correction is made.';
--rollback DROP TABLE core.flag;

--changeset samitava:0004-image
CREATE TABLE core.image (
    id            bigint  GENERATED ALWAYS AS IDENTITY,
    task_id       bigint,
    exercise_id   bigint,
    file_location text    NOT NULL,
    origin        text    NOT NULL,
    source_page   integer NOT NULL,
    CONSTRAINT pk_image PRIMARY KEY (id),
    CONSTRAINT ck_image__one_target CHECK (num_nonnulls(task_id, exercise_id) = 1),
    CONSTRAINT ck_image__origin CHECK (origin IN ('source', 'redrawn')),
    CONSTRAINT ck_image__source_page_positive CHECK (source_page > 0),
    CONSTRAINT fk_image__task FOREIGN KEY (task_id)
        REFERENCES core.task (id) ON DELETE CASCADE,
    CONSTRAINT fk_image__exercise FOREIGN KEY (exercise_id)
        REFERENCES core.exercise (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.image IS 'Image that belongs to a task or to a whole exercise. The file itself is stored outside the database.';
COMMENT ON COLUMN core.image.id IS 'Surrogate key.';
COMMENT ON COLUMN core.image.task_id IS 'Task the image belongs to. Exactly one of task_id and exercise_id is filled.';
COMMENT ON COLUMN core.image.exercise_id IS 'Exercise the image belongs to. Exactly one of task_id and exercise_id is filled.';
COMMENT ON COLUMN core.image.file_location IS 'Address of the file.';
COMMENT ON COLUMN core.image.origin IS 'Origin: source (taken from the document) or redrawn.';
COMMENT ON COLUMN core.image.source_page IS 'Page of the document where the image is.';
--rollback DROP TABLE core.image;
