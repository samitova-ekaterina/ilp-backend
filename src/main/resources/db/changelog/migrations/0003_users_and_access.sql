--liquibase formatted sql

--changeset samitava:0003-app-user
CREATE TABLE core.app_user (
    id                    bigint      GENERATED ALWAYS AS IDENTITY,
    email                 text        NOT NULL,
    password_hash         text        NOT NULL,
    country_id            bigint      NOT NULL,
    age_group             text        NOT NULL,
    registration_role     text        NOT NULL,
    display_name          text,
    interface_language_id bigint      NOT NULL,
    registered_at         timestamptz NOT NULL,
    time_zone             text        NOT NULL,
    daily_task_limit      integer     NOT NULL DEFAULT 30,
    CONSTRAINT pk_app_user PRIMARY KEY (id),
    CONSTRAINT uq_app_user__email UNIQUE (email),
    CONSTRAINT ck_app_user__email_lowercase CHECK (email = lower(email)),
    CONSTRAINT ck_app_user__age_group CHECK (age_group IN ('14-17', 'adult')),
    CONSTRAINT ck_app_user__registration_role CHECK (registration_role IN ('teacher', 'learner')),
    CONSTRAINT ck_app_user__daily_task_limit_positive CHECK (daily_task_limit > 0),
    CONSTRAINT fk_app_user__country FOREIGN KEY (country_id)
        REFERENCES core.country (id) ON DELETE RESTRICT,
    CONSTRAINT fk_app_user__interface_language FOREIGN KEY (interface_language_id)
        REFERENCES core.language (id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.app_user IS 'User account. One account can combine the roles of teacher, learner and self-directed learner.';
COMMENT ON COLUMN core.app_user.id IS 'Surrogate key.';
COMMENT ON COLUMN core.app_user.email IS 'Personal data. E-mail address, stored in lower case. A second registration with the same address is rejected.';
COMMENT ON COLUMN core.app_user.password_hash IS 'Password hash. The password itself is not stored.';
COMMENT ON COLUMN core.app_user.country_id IS 'Country of the user.';
COMMENT ON COLUMN core.app_user.age_group IS 'Age group: 14-17 or adult. The date of birth is not stored.';
COMMENT ON COLUMN core.app_user.registration_role IS 'Role chosen at registration: teacher or learner.';
COMMENT ON COLUMN core.app_user.display_name IS 'Personal data. Name shown to other users. NULL until the user sets it.';
COMMENT ON COLUMN core.app_user.interface_language_id IS 'Language of the user interface.';
COMMENT ON COLUMN core.app_user.registered_at IS 'Moment of registration.';
COMMENT ON COLUMN core.app_user.time_zone IS 'Full time zone name, for example Europe/Vilnius. Defines day boundaries for the queue and deadlines.';
COMMENT ON COLUMN core.app_user.daily_task_limit IS 'Maximum number of tasks in the daily queue.';
--rollback DROP TABLE core.app_user;

--changeset samitava:0003-course
CREATE TABLE core.course (
    id            bigint      GENERATED ALWAYS AS IDENTITY,
    name          text        NOT NULL,
    owner_user_id bigint      NOT NULL,
    created_at    timestamptz NOT NULL,
    CONSTRAINT pk_course PRIMARY KEY (id),
    CONSTRAINT fk_course__owner_user FOREIGN KEY (owner_user_id)
        REFERENCES core.app_user (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.course IS 'Own course of a self-directed learner.';
COMMENT ON COLUMN core.course.id IS 'Surrogate key.';
COMMENT ON COLUMN core.course.name IS 'Course name.';
COMMENT ON COLUMN core.course.owner_user_id IS 'User who owns the course.';
COMMENT ON COLUMN core.course.created_at IS 'Moment of creation.';
--rollback DROP TABLE core.course;

--changeset samitava:0003-study-group
CREATE TABLE core.study_group (
    id                bigint      GENERATED ALWAYS AS IDENTITY,
    name              text        NOT NULL,
    teacher_user_id   bigint      NOT NULL,
    created_at        timestamptz NOT NULL,
    study_language_id bigint      NOT NULL,
    CONSTRAINT pk_study_group PRIMARY KEY (id),
    CONSTRAINT fk_study_group__teacher_user FOREIGN KEY (teacher_user_id)
        REFERENCES core.app_user (id) ON DELETE CASCADE,
    CONSTRAINT fk_study_group__study_language FOREIGN KEY (study_language_id)
        REFERENCES core.language (id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.study_group IS 'Group of learners of one teacher. A group studies one language.';
COMMENT ON COLUMN core.study_group.id IS 'Surrogate key.';
COMMENT ON COLUMN core.study_group.name IS 'Group name.';
COMMENT ON COLUMN core.study_group.teacher_user_id IS 'Teacher who leads the group.';
COMMENT ON COLUMN core.study_group.created_at IS 'Moment of creation.';
COMMENT ON COLUMN core.study_group.study_language_id IS 'Language the group studies.';
--rollback DROP TABLE core.study_group;

--changeset samitava:0003-learning-link
CREATE TABLE core.learning_link (
    id                   bigint      GENERATED ALWAYS AS IDENTITY,
    link_kind            text        NOT NULL,
    learner_user_id      bigint      NOT NULL,
    teacher_user_id      bigint,
    course_id            bigint,
    goal                 text,
    target_cefr_level_id bigint,
    started_at           timestamptz NOT NULL,
    ended_at             timestamptz,
    study_language_id    bigint      NOT NULL,
    CONSTRAINT pk_learning_link PRIMARY KEY (id),
    CONSTRAINT uq_learning_link__course UNIQUE (course_id),
    CONSTRAINT ck_learning_link__link_kind CHECK (link_kind IN ('with_teacher', 'self_directed')),
    CONSTRAINT ck_learning_link__kind_consistency CHECK (
        (link_kind = 'self_directed' AND course_id IS NOT NULL AND teacher_user_id IS NULL)
        OR (link_kind = 'with_teacher' AND course_id IS NULL)
    ),
    -- The teacher reference becomes empty only when the teacher account is deleted;
    -- such a link must already be closed.
    CONSTRAINT ck_learning_link__teacher_present CHECK (
        link_kind <> 'with_teacher' OR teacher_user_id IS NOT NULL OR ended_at IS NOT NULL
    ),
    CONSTRAINT ck_learning_link__ended_after_started CHECK (ended_at >= started_at),
    CONSTRAINT fk_learning_link__learner_user FOREIGN KEY (learner_user_id)
        REFERENCES core.app_user (id) ON DELETE CASCADE,
    CONSTRAINT fk_learning_link__teacher_user FOREIGN KEY (teacher_user_id)
        REFERENCES core.app_user (id) ON DELETE SET NULL,
    CONSTRAINT fk_learning_link__course FOREIGN KEY (course_id)
        REFERENCES core.course (id) ON DELETE CASCADE,
    CONSTRAINT fk_learning_link__target_cefr_level FOREIGN KEY (target_cefr_level_id)
        REFERENCES core.cefr_level (id) ON DELETE RESTRICT,
    CONSTRAINT fk_learning_link__study_language FOREIGN KEY (study_language_id)
        REFERENCES core.language (id) ON DELETE RESTRICT
);
-- Uniqueness only among open links, so it is a partial unique index, not a table constraint.
CREATE UNIQUE INDEX uq_learning_link__open_triple
    ON core.learning_link (learner_user_id, teacher_user_id, study_language_id)
    WHERE ended_at IS NULL;
COMMENT ON TABLE core.learning_link IS 'Learning link: a learner with a teacher, or a learner with an own course. History, answers and level belong to the link, not to the person.';
COMMENT ON COLUMN core.learning_link.id IS 'Surrogate key.';
COMMENT ON COLUMN core.learning_link.link_kind IS 'Kind of link: with_teacher or self_directed.';
COMMENT ON COLUMN core.learning_link.learner_user_id IS 'User who learns.';
COMMENT ON COLUMN core.learning_link.teacher_user_id IS 'Teacher. NULL for a self-directed link and after the teacher account is deleted.';
COMMENT ON COLUMN core.learning_link.course_id IS 'Own course. Filled for a self-directed link only.';
COMMENT ON COLUMN core.learning_link.goal IS 'Learning goal in the words of the user. NULL until set.';
COMMENT ON COLUMN core.learning_link.target_cefr_level_id IS 'Target CEFR level. NULL until the goal is set.';
COMMENT ON COLUMN core.learning_link.started_at IS 'Moment the link started.';
COMMENT ON COLUMN core.learning_link.ended_at IS 'Moment the link ended. NULL while the link is active. After it the teacher sees nothing further.';
COMMENT ON COLUMN core.learning_link.study_language_id IS 'Language studied within the link.';
--rollback DROP TABLE core.learning_link;

--changeset samitava:0003-consent
CREATE TABLE core.consent (
    id                bigint      GENERATED ALWAYS AS IDENTITY,
    app_user_id       bigint      NOT NULL,
    consent_kind      text        NOT NULL,
    given_at          timestamptz NOT NULL,
    policy_version_id bigint      NOT NULL,
    withdrawn_at      timestamptz,
    CONSTRAINT pk_consent PRIMARY KEY (id),
    CONSTRAINT ck_consent__consent_kind CHECK (consent_kind IN ('main', 'statistics')),
    CONSTRAINT ck_consent__withdrawn_after_given CHECK (withdrawn_at >= given_at),
    CONSTRAINT fk_consent__app_user FOREIGN KEY (app_user_id)
        REFERENCES core.app_user (id) ON DELETE CASCADE,
    CONSTRAINT fk_consent__policy_version FOREIGN KEY (policy_version_id)
        REFERENCES core.policy_version (id) ON DELETE RESTRICT
);
-- Withdrawn consents stay as history, so uniqueness applies to active ones only.
CREATE UNIQUE INDEX uq_consent__active
    ON core.consent (app_user_id, consent_kind)
    WHERE withdrawn_at IS NULL;
COMMENT ON TABLE core.consent IS 'Consent of a user, kept together with the policy version it was given under.';
COMMENT ON COLUMN core.consent.id IS 'Surrogate key.';
COMMENT ON COLUMN core.consent.app_user_id IS 'User who gave the consent.';
COMMENT ON COLUMN core.consent.consent_kind IS 'Kind of consent: main or statistics.';
COMMENT ON COLUMN core.consent.given_at IS 'Moment the consent was given.';
COMMENT ON COLUMN core.consent.policy_version_id IS 'Policy version the consent was given under.';
COMMENT ON COLUMN core.consent.withdrawn_at IS 'Moment the consent was withdrawn. NULL while the consent is active.';
--rollback DROP TABLE core.consent;

--changeset samitava:0003-invitation
CREATE TABLE core.invitation (
    id             bigint      GENERATED ALWAYS AS IDENTITY,
    study_group_id bigint      NOT NULL,
    code           text        NOT NULL,
    valid_until    timestamptz NOT NULL,
    revoked_at     timestamptz,
    CONSTRAINT pk_invitation PRIMARY KEY (id),
    CONSTRAINT uq_invitation__code UNIQUE (code),
    CONSTRAINT fk_invitation__study_group FOREIGN KEY (study_group_id)
        REFERENCES core.study_group (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.invitation IS 'Invitation to join a group by a link.';
COMMENT ON COLUMN core.invitation.id IS 'Surrogate key.';
COMMENT ON COLUMN core.invitation.study_group_id IS 'Group the invitation leads to.';
COMMENT ON COLUMN core.invitation.code IS 'Random value from which the link address is built.';
COMMENT ON COLUMN core.invitation.valid_until IS 'Moment until which the invitation is valid.';
COMMENT ON COLUMN core.invitation.revoked_at IS 'Moment the invitation was revoked. NULL while not revoked.';
--rollback DROP TABLE core.invitation;

--changeset samitava:0003-erasure-request
CREATE TABLE core.erasure_request (
    id                     bigint      GENERATED ALWAYS AS IDENTITY,
    app_user_id            bigint,
    learning_link_id       bigint,
    requested_at           timestamptz NOT NULL,
    confirm_by             timestamptz NOT NULL,
    confirmed_at           timestamptz,
    execute_by             timestamptz,
    status                 text        NOT NULL,
    scope                  text        NOT NULL,
    confirmation_code_hash text,
    CONSTRAINT pk_erasure_request PRIMARY KEY (id),
    CONSTRAINT ck_erasure_request__status CHECK (
        status IN ('awaiting_confirmation', 'confirmed', 'executed', 'cancelled')
    ),
    CONSTRAINT ck_erasure_request__scope CHECK (scope IN ('single_link', 'everything')),
    CONSTRAINT fk_erasure_request__app_user FOREIGN KEY (app_user_id)
        REFERENCES core.app_user (id) ON DELETE SET NULL,
    CONSTRAINT fk_erasure_request__learning_link FOREIGN KEY (learning_link_id)
        REFERENCES core.learning_link (id) ON DELETE SET NULL
);
COMMENT ON TABLE core.erasure_request IS 'Request of a user to erase personal data. The record outlives the erasure, without references to the person.';
COMMENT ON COLUMN core.erasure_request.id IS 'Surrogate key.';
COMMENT ON COLUMN core.erasure_request.app_user_id IS 'User who made the request. Becomes NULL after the account is deleted.';
COMMENT ON COLUMN core.erasure_request.learning_link_id IS 'Learning link to erase. Becomes NULL after the erasure.';
COMMENT ON COLUMN core.erasure_request.requested_at IS 'Moment of the request.';
COMMENT ON COLUMN core.erasure_request.confirm_by IS 'Moment by which the request must be confirmed, otherwise it is cancelled.';
COMMENT ON COLUMN core.erasure_request.confirmed_at IS 'Moment of confirmation. NULL until confirmed.';
COMMENT ON COLUMN core.erasure_request.execute_by IS 'Moment before which the erasure is not carried out. NULL when no term is set.';
COMMENT ON COLUMN core.erasure_request.status IS 'State: awaiting_confirmation, confirmed, executed or cancelled.';
COMMENT ON COLUMN core.erasure_request.scope IS 'What is erased: single_link or everything.';
COMMENT ON COLUMN core.erasure_request.confirmation_code_hash IS 'Hash of the confirmation code sent by e-mail. Cleared after confirmation or cancellation.';
--rollback DROP TABLE core.erasure_request;

--changeset samitava:0003-group-membership
CREATE TABLE core.group_membership (
    id               bigint      GENERATED ALWAYS AS IDENTITY,
    learning_link_id bigint      NOT NULL,
    study_group_id   bigint      NOT NULL,
    joined_at        timestamptz NOT NULL,
    left_at          timestamptz,
    CONSTRAINT pk_group_membership PRIMARY KEY (id),
    CONSTRAINT ck_group_membership__left_after_joined CHECK (left_at >= joined_at),
    CONSTRAINT fk_group_membership__learning_link FOREIGN KEY (learning_link_id)
        REFERENCES core.learning_link (id) ON DELETE CASCADE,
    CONSTRAINT fk_group_membership__study_group FOREIGN KEY (study_group_id)
        REFERENCES core.study_group (id) ON DELETE CASCADE
);
-- A learner may leave a group and return, so the pair is unique only among current members.
CREATE UNIQUE INDEX uq_group_membership__active
    ON core.group_membership (learning_link_id, study_group_id)
    WHERE left_at IS NULL;
COMMENT ON TABLE core.group_membership IS 'Membership of a learning link in a group, with its history.';
COMMENT ON COLUMN core.group_membership.id IS 'Surrogate key.';
COMMENT ON COLUMN core.group_membership.learning_link_id IS 'Learning link of the member.';
COMMENT ON COLUMN core.group_membership.study_group_id IS 'Group.';
COMMENT ON COLUMN core.group_membership.joined_at IS 'Moment of joining.';
COMMENT ON COLUMN core.group_membership.left_at IS 'Moment of leaving. NULL while a member. Results stay in the group archive afterwards.';
--rollback DROP TABLE core.group_membership;
