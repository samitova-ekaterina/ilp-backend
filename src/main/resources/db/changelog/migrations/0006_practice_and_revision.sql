--liquibase formatted sql

--changeset samitava:0006-answer
CREATE TABLE core.answer (
    id                     bigint      GENERATED ALWAYS AS IDENTITY,
    task_id                bigint      NOT NULL,
    learning_link_id       bigint      NOT NULL,
    homework_assignment_id bigint,
    content                jsonb       NOT NULL,
    result                 text        NOT NULL,
    attempt_number         integer     NOT NULL,
    response_time_ms       integer     NOT NULL,
    active_time_ms         integer     NOT NULL,
    answered_at            timestamptz NOT NULL,
    answer_change_count    integer     NOT NULL DEFAULT 0,
    answer_rating          text,
    lesson_exercise_id     bigint,
    CONSTRAINT pk_answer PRIMARY KEY (id),
    CONSTRAINT ck_answer__result CHECK (result IN ('correct', 'incorrect', 'awaiting_review')),
    CONSTRAINT ck_answer__attempt_number_positive CHECK (attempt_number >= 1),
    CONSTRAINT ck_answer__response_time_not_negative CHECK (response_time_ms >= 0),
    CONSTRAINT ck_answer__active_time_within_response CHECK (active_time_ms <= response_time_ms),
    CONSTRAINT ck_answer__answer_change_count_not_negative CHECK (answer_change_count >= 0),
    CONSTRAINT ck_answer__answer_rating CHECK (
        answer_rating IN ('error', 'slow_and_changed', 'moderate', 'fast')
    ),
    CONSTRAINT fk_answer__task FOREIGN KEY (task_id)
        REFERENCES core.task (id) ON DELETE CASCADE,
    CONSTRAINT fk_answer__learning_link FOREIGN KEY (learning_link_id)
        REFERENCES core.learning_link (id) ON DELETE CASCADE,
    CONSTRAINT fk_answer__homework_assignment FOREIGN KEY (homework_assignment_id)
        REFERENCES core.homework_assignment (id) ON DELETE SET NULL,
    CONSTRAINT fk_answer__lesson_exercise FOREIGN KEY (lesson_exercise_id)
        REFERENCES core.lesson_exercise (id) ON DELETE SET NULL
);
COMMENT ON TABLE core.answer IS 'Answer of a learner to a task. One task can be answered many times: in a lesson, in homework, at each revision.';
COMMENT ON COLUMN core.answer.id IS 'Surrogate key.';
COMMENT ON COLUMN core.answer.task_id IS 'Task that was answered.';
COMMENT ON COLUMN core.answer.learning_link_id IS 'Learning link of the learner.';
COMMENT ON COLUMN core.answer.homework_assignment_id IS 'Homework the answer was given for. NULL when not given for homework.';
COMMENT ON COLUMN core.answer.content IS 'Content of the answer. Its structure is defined by the exercise type.';
COMMENT ON COLUMN core.answer.result IS 'Result: correct, incorrect or awaiting_review (to be checked by a person).';
COMMENT ON COLUMN core.answer.attempt_number IS 'Number of the attempt within one pass through the task.';
COMMENT ON COLUMN core.answer.response_time_ms IS 'Response time in milliseconds.';
COMMENT ON COLUMN core.answer.active_time_ms IS 'Active time in milliseconds: response time without long pauses.';
COMMENT ON COLUMN core.answer.answered_at IS 'Moment the answer was given.';
COMMENT ON COLUMN core.answer.answer_change_count IS 'How many times the learner changed the answer before sending it.';
COMMENT ON COLUMN core.answer.answer_rating IS 'Rating derived by the system: error, slow_and_changed, moderate or fast. NULL while the answer awaits review.';
COMMENT ON COLUMN core.answer.lesson_exercise_id IS 'Showing of the exercise in a lesson during which the answer was given. NULL when not given in a lesson.';
--rollback DROP TABLE core.answer;

--changeset samitava:0006-revision-record
CREATE TABLE core.revision_record (
    id                    bigint       GENERATED ALWAYS AS IDENTITY,
    task_id               bigint       NOT NULL,
    learning_link_id      bigint       NOT NULL,
    next_revision_date    date         NOT NULL,
    current_interval_days integer      NOT NULL,
    ease                  numeric(4,2) NOT NULL DEFAULT 2.50,
    CONSTRAINT pk_revision_record PRIMARY KEY (id),
    CONSTRAINT uq_revision_record__pair UNIQUE (learning_link_id, task_id),
    CONSTRAINT ck_revision_record__interval_positive CHECK (current_interval_days >= 1),
    CONSTRAINT ck_revision_record__ease_min CHECK (ease >= 1.30),
    CONSTRAINT fk_revision_record__task FOREIGN KEY (task_id)
        REFERENCES core.task (id) ON DELETE CASCADE,
    CONSTRAINT fk_revision_record__learning_link FOREIGN KEY (learning_link_id)
        REFERENCES core.learning_link (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.revision_record IS 'Spaced repetition schedule of one task for one learning link.';
COMMENT ON COLUMN core.revision_record.id IS 'Surrogate key.';
COMMENT ON COLUMN core.revision_record.task_id IS 'Task to revise.';
COMMENT ON COLUMN core.revision_record.learning_link_id IS 'Learning link of the learner.';
COMMENT ON COLUMN core.revision_record.next_revision_date IS 'Date of the next revision. The daily queue is built by it.';
COMMENT ON COLUMN core.revision_record.current_interval_days IS 'Current interval in days. Grows after a correct answer.';
COMMENT ON COLUMN core.revision_record.ease IS 'Ease factor by which the interval grows after a correct answer.';
--rollback DROP TABLE core.revision_record;
