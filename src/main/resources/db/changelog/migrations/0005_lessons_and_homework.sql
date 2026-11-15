--liquibase formatted sql

--changeset samitava:0005-lesson
CREATE TABLE core.lesson (
    id               bigint      GENERATED ALWAYS AS IDENTITY,
    study_group_id   bigint,
    learning_link_id bigint,
    started_at       timestamptz NOT NULL,
    ended_at         timestamptz,
    CONSTRAINT pk_lesson PRIMARY KEY (id),
    CONSTRAINT ck_lesson__one_target CHECK (num_nonnulls(study_group_id, learning_link_id) = 1),
    CONSTRAINT ck_lesson__ended_after_started CHECK (ended_at >= started_at),
    CONSTRAINT fk_lesson__study_group FOREIGN KEY (study_group_id)
        REFERENCES core.study_group (id) ON DELETE CASCADE,
    CONSTRAINT fk_lesson__learning_link FOREIGN KEY (learning_link_id)
        REFERENCES core.learning_link (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.lesson IS 'Lesson held by a teacher: with a group or with one learner.';
COMMENT ON COLUMN core.lesson.id IS 'Surrogate key.';
COMMENT ON COLUMN core.lesson.study_group_id IS 'Group, for a group lesson. Exactly one of study_group_id and learning_link_id is filled.';
COMMENT ON COLUMN core.lesson.learning_link_id IS 'Learning link, for an individual lesson. Exactly one of study_group_id and learning_link_id is filled.';
COMMENT ON COLUMN core.lesson.started_at IS 'Moment the lesson started.';
COMMENT ON COLUMN core.lesson.ended_at IS 'Moment the lesson ended. NULL while the lesson is in progress.';
--rollback DROP TABLE core.lesson;

--changeset samitava:0005-lesson-exercise
CREATE TABLE core.lesson_exercise (
    id                        bigint      GENERATED ALWAYS AS IDENTITY,
    lesson_id                 bigint      NOT NULL,
    exercise_id               bigint      NOT NULL,
    shown_to_learning_link_id bigint,
    opened_at                 timestamptz NOT NULL,
    CONSTRAINT pk_lesson_exercise PRIMARY KEY (id),
    CONSTRAINT fk_lesson_exercise__lesson FOREIGN KEY (lesson_id)
        REFERENCES core.lesson (id) ON DELETE CASCADE,
    CONSTRAINT fk_lesson_exercise__exercise FOREIGN KEY (exercise_id)
        REFERENCES core.exercise (id) ON DELETE CASCADE,
    CONSTRAINT fk_lesson_exercise__shown_to_learning_link FOREIGN KEY (shown_to_learning_link_id)
        REFERENCES core.learning_link (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.lesson_exercise IS 'Exercise opened by the teacher during a lesson.';
COMMENT ON COLUMN core.lesson_exercise.id IS 'Surrogate key.';
COMMENT ON COLUMN core.lesson_exercise.lesson_id IS 'Lesson.';
COMMENT ON COLUMN core.lesson_exercise.exercise_id IS 'Exercise that was opened.';
COMMENT ON COLUMN core.lesson_exercise.shown_to_learning_link_id IS 'Learning link of the learner the exercise was shown to. NULL when shown to everyone.';
COMMENT ON COLUMN core.lesson_exercise.opened_at IS 'Moment the exercise was opened.';
--rollback DROP TABLE core.lesson_exercise;

--changeset samitava:0005-homework
CREATE TABLE core.homework (
    id                     bigint      GENERATED ALWAYS AS IDENTITY,
    assigned_by_user_id    bigint      NOT NULL,
    study_group_id         bigint,
    due_at                 timestamptz NOT NULL,
    assigned_at            timestamptz NOT NULL,
    adaptation_proposal_id bigint,
    CONSTRAINT pk_homework PRIMARY KEY (id),
    CONSTRAINT ck_homework__due_after_assigned CHECK (due_at >= assigned_at),
    CONSTRAINT fk_homework__assigned_by_user FOREIGN KEY (assigned_by_user_id)
        REFERENCES core.app_user (id) ON DELETE CASCADE,
    CONSTRAINT fk_homework__study_group FOREIGN KEY (study_group_id)
        REFERENCES core.study_group (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.homework IS 'Homework assigned by a teacher to a group or to one learner.';
COMMENT ON COLUMN core.homework.id IS 'Surrogate key.';
COMMENT ON COLUMN core.homework.assigned_by_user_id IS 'Teacher who assigned the homework.';
COMMENT ON COLUMN core.homework.study_group_id IS 'Group the homework is assigned to. NULL when assigned to one learner.';
COMMENT ON COLUMN core.homework.due_at IS 'Deadline, as a moment in time.';
COMMENT ON COLUMN core.homework.assigned_at IS 'Moment of assignment.';
COMMENT ON COLUMN core.homework.adaptation_proposal_id IS 'Adaptation proposal the homework was created from. NULL when assigned manually.';
--rollback DROP TABLE core.homework;

--changeset samitava:0005-homework-assignment
CREATE TABLE core.homework_assignment (
    id               bigint      GENERATED ALWAYS AS IDENTITY,
    homework_id      bigint      NOT NULL,
    learning_link_id bigint      NOT NULL,
    personal_note    text,
    completed_at     timestamptz,
    CONSTRAINT pk_homework_assignment PRIMARY KEY (id),
    CONSTRAINT uq_homework_assignment__pair UNIQUE (homework_id, learning_link_id),
    CONSTRAINT fk_homework_assignment__homework FOREIGN KEY (homework_id)
        REFERENCES core.homework (id) ON DELETE CASCADE,
    CONSTRAINT fk_homework_assignment__learning_link FOREIGN KEY (learning_link_id)
        REFERENCES core.learning_link (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.homework_assignment IS 'Homework as received by one learner.';
COMMENT ON COLUMN core.homework_assignment.id IS 'Surrogate key.';
COMMENT ON COLUMN core.homework_assignment.homework_id IS 'Homework.';
COMMENT ON COLUMN core.homework_assignment.learning_link_id IS 'Learning link of the learner who received it.';
COMMENT ON COLUMN core.homework_assignment.personal_note IS 'Note visible to this learner only. NULL when there is none.';
COMMENT ON COLUMN core.homework_assignment.completed_at IS 'Moment of completion. NULL until completed. Completion is counted by the main items; additional items do not affect it.';
--rollback DROP TABLE core.homework_assignment;

--changeset samitava:0005-homework-exercise
CREATE TABLE core.homework_exercise (
    homework_id bigint  NOT NULL,
    exercise_id bigint  NOT NULL,
    sort_order  integer NOT NULL,
    item_kind   text    NOT NULL DEFAULT 'main',
    CONSTRAINT pk_homework_exercise PRIMARY KEY (homework_id, exercise_id),
    CONSTRAINT uq_homework_exercise__order UNIQUE (homework_id, sort_order),
    CONSTRAINT ck_homework_exercise__sort_order_positive CHECK (sort_order > 0),
    CONSTRAINT ck_homework_exercise__item_kind CHECK (item_kind IN ('main', 'additional')),
    CONSTRAINT fk_homework_exercise__homework FOREIGN KEY (homework_id)
        REFERENCES core.homework (id) ON DELETE CASCADE,
    CONSTRAINT fk_homework_exercise__exercise FOREIGN KEY (exercise_id)
        REFERENCES core.exercise (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.homework_exercise IS 'Whole exercise included in a homework.';
COMMENT ON COLUMN core.homework_exercise.homework_id IS 'Homework.';
COMMENT ON COLUMN core.homework_exercise.exercise_id IS 'Exercise included in it.';
COMMENT ON COLUMN core.homework_exercise.sort_order IS 'Position of the exercise in the homework.';
COMMENT ON COLUMN core.homework_exercise.item_kind IS 'Kind: main or additional. Additional items are harder and optional.';
--rollback DROP TABLE core.homework_exercise;

--changeset samitava:0005-homework-task
CREATE TABLE core.homework_task (
    homework_id bigint  NOT NULL,
    task_id     bigint  NOT NULL,
    sort_order  integer NOT NULL,
    item_kind   text    NOT NULL DEFAULT 'main',
    CONSTRAINT pk_homework_task PRIMARY KEY (homework_id, task_id),
    CONSTRAINT uq_homework_task__order UNIQUE (homework_id, sort_order),
    CONSTRAINT ck_homework_task__sort_order_positive CHECK (sort_order > 0),
    CONSTRAINT ck_homework_task__item_kind CHECK (item_kind IN ('main', 'additional')),
    CONSTRAINT fk_homework_task__homework FOREIGN KEY (homework_id)
        REFERENCES core.homework (id) ON DELETE CASCADE,
    CONSTRAINT fk_homework_task__task FOREIGN KEY (task_id)
        REFERENCES core.task (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.homework_task IS 'Separate task included in a homework.';
COMMENT ON COLUMN core.homework_task.homework_id IS 'Homework.';
COMMENT ON COLUMN core.homework_task.task_id IS 'Task included in it.';
COMMENT ON COLUMN core.homework_task.sort_order IS 'Position of the task in the homework.';
COMMENT ON COLUMN core.homework_task.item_kind IS 'Kind: main or additional. Additional items are harder and optional.';
--rollback DROP TABLE core.homework_task;
