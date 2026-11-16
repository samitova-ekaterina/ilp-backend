--liquibase formatted sql

--changeset samitava:0015-competition
CREATE TABLE core.competition (
    id                   bigint      GENERATED ALWAYS AS IDENTITY,
    lesson_id            bigint,
    scale_id             bigint,
    level_step_id        bigint,
    exercise_type_id     bigint,
    answer_time_limit_ms integer     NOT NULL DEFAULT 240000,
    started_at           timestamptz NOT NULL,
    ended_at             timestamptz,
    exercise_id          bigint,
    practice_task_count  integer     NOT NULL DEFAULT 1,
    scored_task_count    integer,
    CONSTRAINT pk_competition PRIMARY KEY (id),
    CONSTRAINT ck_competition__lesson_or_matched CHECK (
        (lesson_id IS NOT NULL AND exercise_id IS NOT NULL
            AND scale_id IS NULL AND level_step_id IS NULL AND exercise_type_id IS NULL)
        OR (lesson_id IS NULL AND exercise_id IS NULL
            AND scale_id IS NOT NULL AND exercise_type_id IS NOT NULL)
    ),
    CONSTRAINT ck_competition__answer_time_limit_positive CHECK (answer_time_limit_ms > 0),
    CONSTRAINT ck_competition__ended_after_started CHECK (ended_at >= started_at),
    CONSTRAINT ck_competition__practice_task_count_not_negative CHECK (practice_task_count >= 0),
    CONSTRAINT ck_competition__scored_task_count_positive CHECK (scored_task_count > 0),
    CONSTRAINT fk_competition__lesson FOREIGN KEY (lesson_id)
        REFERENCES core.lesson (id) ON DELETE CASCADE,
    CONSTRAINT fk_competition__scale FOREIGN KEY (scale_id)
        REFERENCES core.scale (id) ON DELETE RESTRICT,
    CONSTRAINT fk_competition__level_step FOREIGN KEY (level_step_id)
        REFERENCES core.level_step (id) ON DELETE RESTRICT,
    CONSTRAINT fk_competition__exercise_type FOREIGN KEY (exercise_type_id)
        REFERENCES core.exercise_type (id) ON DELETE RESTRICT,
    CONSTRAINT fk_competition__exercise FOREIGN KEY (exercise_id)
        REFERENCES core.exercise (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.competition IS 'Competition: either held in a lesson on one exercise, or matched by the system among learners of equal level. Correctness is scored, not speed. The state is derived from the dates.';
COMMENT ON COLUMN core.competition.id IS 'Surrogate key.';
COMMENT ON COLUMN core.competition.lesson_id IS 'Lesson the competition is held in. NULL for a competition outside a lesson.';
COMMENT ON COLUMN core.competition.scale_id IS 'Scale by which equal participants are matched. Filled only outside a lesson.';
COMMENT ON COLUMN core.competition.level_step_id IS 'Level step of the participants. Only outside a lesson; NULL for a competition composed by a teacher.';
COMMENT ON COLUMN core.competition.exercise_type_id IS 'Exercise type familiar to all participants. Filled only outside a lesson.';
COMMENT ON COLUMN core.competition.answer_time_limit_ms IS 'Time allowed for one answer, in milliseconds. A ceiling, not a race: there is no countdown and speed is not scored. When it expires the task counts as unanswered.';
COMMENT ON COLUMN core.competition.started_at IS 'Moment the competition started.';
COMMENT ON COLUMN core.competition.ended_at IS 'Moment the competition ended. NULL while it is in progress.';
COMMENT ON COLUMN core.competition.exercise_id IS 'Exercise the competition is held on. Filled only in a lesson.';
COMMENT ON COLUMN core.competition.practice_task_count IS 'Number of practice tasks before the scored ones.';
COMMENT ON COLUMN core.competition.scored_task_count IS 'Number of scored tasks. Outside a lesson, 10 by default; in a lesson it is NULL and derived from the exercise.';
--rollback DROP TABLE core.competition;

--changeset samitava:0015-competition-participation
CREATE TABLE core.competition_participation (
    id               bigint      GENERATED ALWAYS AS IDENTITY,
    competition_id   bigint      NOT NULL,
    learning_link_id bigint      NOT NULL,
    nickname         text,
    team_number      integer,
    joined_at        timestamptz NOT NULL,
    CONSTRAINT pk_competition_participation PRIMARY KEY (id),
    CONSTRAINT uq_competition_participation__pair UNIQUE (competition_id, learning_link_id),
    CONSTRAINT uq_competition_participation__nickname UNIQUE (competition_id, nickname),
    CONSTRAINT ck_competition_participation__team_number_positive CHECK (team_number > 0),
    CONSTRAINT fk_competition_participation__competition FOREIGN KEY (competition_id)
        REFERENCES core.competition (id) ON DELETE CASCADE,
    CONSTRAINT fk_competition_participation__learning_link FOREIGN KEY (learning_link_id)
        REFERENCES core.learning_link (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.competition_participation IS 'Participation of a learner in a competition. A learner joins only by own action.';
COMMENT ON COLUMN core.competition_participation.id IS 'Surrogate key.';
COMMENT ON COLUMN core.competition_participation.competition_id IS 'Competition.';
COMMENT ON COLUMN core.competition_participation.learning_link_id IS 'Learning link of the participant.';
COMMENT ON COLUMN core.competition_participation.nickname IS 'Nickname shown to other participants, unique within the competition. NULL in a lesson.';
COMMENT ON COLUMN core.competition_participation.team_number IS 'Team number. NULL when everyone competes individually.';
COMMENT ON COLUMN core.competition_participation.joined_at IS 'Moment the learner joined.';
--rollback DROP TABLE core.competition_participation;

--changeset samitava:0015-answer-competition-participation-fk
ALTER TABLE core.answer
    ADD CONSTRAINT fk_answer__competition_participation FOREIGN KEY (competition_participation_id)
        REFERENCES core.competition_participation (id) ON DELETE SET NULL;
--rollback ALTER TABLE core.answer DROP CONSTRAINT fk_answer__competition_participation;
