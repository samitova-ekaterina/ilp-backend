--liquibase formatted sql

--changeset samitava:0013-answer-error-type-and-review
ALTER TABLE core.answer
    ADD COLUMN error_type_id                bigint,
    ADD COLUMN competition_participation_id bigint,
    ADD COLUMN shown_as_exercise_type_id    bigint,
    ADD COLUMN audio_location               text,
    ADD COLUMN reviewed_at                  timestamptz,
    ADD CONSTRAINT fk_answer__error_type FOREIGN KEY (error_type_id)
        REFERENCES core.error_type (id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_answer__shown_as_exercise_type FOREIGN KEY (shown_as_exercise_type_id)
        REFERENCES core.exercise_type (id) ON DELETE RESTRICT;
COMMENT ON COLUMN core.answer.error_type_id IS 'Type of the mistake. NULL for a correct answer and until the type is determined.';
COMMENT ON COLUMN core.answer.competition_participation_id IS 'Participation in a competition within which the answer was given. NULL for an ordinary answer.';
COMMENT ON COLUMN core.answer.shown_as_exercise_type_id IS 'Exercise type in which the task was shown. NULL when it was shown in the own type of the exercise.';
COMMENT ON COLUMN core.answer.audio_location IS 'Address of the audio recording. NULL when the answer is not audio.';
COMMENT ON COLUMN core.answer.reviewed_at IS 'Moment the answer was reviewed by a person. NULL for an answer checked automatically.';
--rollback ALTER TABLE core.answer DROP COLUMN reviewed_at, DROP COLUMN audio_location, DROP COLUMN shown_as_exercise_type_id, DROP COLUMN competition_participation_id, DROP COLUMN error_type_id;

--changeset samitava:0013-revision-record-deferral
ALTER TABLE core.revision_record
    ADD COLUMN deferred_at       timestamptz,
    ADD COLUMN deferral_end_date date;
COMMENT ON COLUMN core.revision_record.deferred_at IS 'Moment the task was deferred. NULL when it was never deferred. Not cleared when the task returns to the queue.';
COMMENT ON COLUMN core.revision_record.deferral_end_date IS 'Last day of the deferral. For a self-directed learner the system sets it 7 days ahead; for a learner with a teacher it is NULL until the teacher decides. The task is deferred now when deferred_at is filled and this date is NULL or not yet reached.';
--rollback ALTER TABLE core.revision_record DROP COLUMN deferral_end_date, DROP COLUMN deferred_at;

--changeset samitava:0013-topic-priority
CREATE TABLE core.topic_priority (
    id               bigint      GENERATED ALWAYS AS IDENTITY,
    learning_link_id bigint      NOT NULL,
    topic_id         bigint      NOT NULL,
    raised_at        timestamptz NOT NULL,
    end_date         date        NOT NULL,
    CONSTRAINT pk_topic_priority PRIMARY KEY (id),
    CONSTRAINT fk_topic_priority__learning_link FOREIGN KEY (learning_link_id)
        REFERENCES core.learning_link (id) ON DELETE CASCADE,
    CONSTRAINT fk_topic_priority__topic FOREIGN KEY (topic_id)
        REFERENCES core.topic (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.topic_priority IS 'Raised priority of a topic for a learning link: tasks of the topic come up more often until the end date.';
COMMENT ON COLUMN core.topic_priority.id IS 'Surrogate key.';
COMMENT ON COLUMN core.topic_priority.learning_link_id IS 'Learning link the priority is raised for.';
COMMENT ON COLUMN core.topic_priority.topic_id IS 'Topic whose priority is raised.';
COMMENT ON COLUMN core.topic_priority.raised_at IS 'Moment the priority was raised.';
COMMENT ON COLUMN core.topic_priority.end_date IS 'Last day of the raised priority. Early cancellation is recorded as an end date equal to the current day.';
--rollback DROP TABLE core.topic_priority;
