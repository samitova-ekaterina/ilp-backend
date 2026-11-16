--liquibase formatted sql

--changeset samitava:0011-app-user-reminders
ALTER TABLE core.app_user
    ADD COLUMN reminder_time         time,
    ADD COLUMN reminders_enabled     boolean NOT NULL DEFAULT false,
    ADD COLUMN last_reminder_sent_at timestamptz;
COMMENT ON COLUMN core.app_user.reminder_time IS 'Time of day for the reminder e-mail, in the user time zone. NULL until the user chooses a time.';
COMMENT ON COLUMN core.app_user.reminders_enabled IS 'Whether reminder e-mails are sent. Kept apart from the time so that switching off does not erase the chosen time.';
COMMENT ON COLUMN core.app_user.last_reminder_sent_at IS 'Moment the last reminder e-mail was sent. NULL until the first one. Used to send at most one e-mail a day.';
--rollback ALTER TABLE core.app_user DROP COLUMN last_reminder_sent_at, DROP COLUMN reminders_enabled, DROP COLUMN reminder_time;

--changeset samitava:0011-learning-link-settings
ALTER TABLE core.learning_link
    ADD COLUMN level_decision_mode      text         NOT NULL,
    ADD COLUMN adaptation_decision_mode text         NOT NULL,
    ADD COLUMN queue_decision_mode      text         NOT NULL,
    ADD COLUMN total_course_hours       integer,
    ADD COLUMN desired_end_date         date,
    ADD COLUMN new_material_share       numeric(3,2) NOT NULL DEFAULT 0.10,
    ADD COLUMN failures_before_deferral integer      NOT NULL DEFAULT 8,
    ADD CONSTRAINT ck_learning_link__level_decision_mode CHECK (level_decision_mode IN ('self', 'system')),
    ADD CONSTRAINT ck_learning_link__adaptation_decision_mode CHECK (adaptation_decision_mode IN ('self', 'system')),
    ADD CONSTRAINT ck_learning_link__queue_decision_mode CHECK (queue_decision_mode IN ('self', 'system')),
    ADD CONSTRAINT ck_learning_link__total_course_hours_positive CHECK (total_course_hours > 0),
    ADD CONSTRAINT ck_learning_link__new_material_share_range CHECK (new_material_share BETWEEN 0 AND 1),
    ADD CONSTRAINT ck_learning_link__failures_before_deferral_positive CHECK (failures_before_deferral > 0);
COMMENT ON COLUMN core.learning_link.level_decision_mode IS 'Who records a level change: self (the user decides) or system (the system is trusted).';
COMMENT ON COLUMN core.learning_link.adaptation_decision_mode IS 'Who approves an adaptation proposal: self (the user decides) or system (the system is trusted).';
COMMENT ON COLUMN core.learning_link.queue_decision_mode IS 'Who decides on the revision queue: self (the user decides) or system (the system is trusted).';
COMMENT ON COLUMN core.learning_link.total_course_hours IS 'Total time budget of the course in hours. NULL until it is set.';
COMMENT ON COLUMN core.learning_link.desired_end_date IS 'Date by which the learner wants to finish. NULL until it is set.';
COMMENT ON COLUMN core.learning_link.new_material_share IS 'Share of new material in the daily queue, from 0 to 1. The learner can change it.';
COMMENT ON COLUMN core.learning_link.failures_before_deferral IS 'Number of failed attempts after which a task is deferred instead of being repeated.';
--rollback ALTER TABLE core.learning_link DROP COLUMN failures_before_deferral, DROP COLUMN new_material_share, DROP COLUMN desired_end_date, DROP COLUMN total_course_hours, DROP COLUMN queue_decision_mode, DROP COLUMN adaptation_decision_mode, DROP COLUMN level_decision_mode;

--changeset samitava:0011-export-request
CREATE TABLE core.export_request (
    id               bigint      GENERATED ALWAYS AS IDENTITY,
    app_user_id      bigint      NOT NULL,
    learning_link_id bigint,
    requested_at     timestamptz NOT NULL,
    prepare_by       timestamptz NOT NULL,
    prepared_at      timestamptz,
    file_location    text,
    available_until  timestamptz,
    CONSTRAINT pk_export_request PRIMARY KEY (id),
    CONSTRAINT fk_export_request__app_user FOREIGN KEY (app_user_id)
        REFERENCES core.app_user (id) ON DELETE CASCADE,
    CONSTRAINT fk_export_request__learning_link FOREIGN KEY (learning_link_id)
        REFERENCES core.learning_link (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.export_request IS 'Request of a user to export own data. The state of the request is derived from its dates.';
COMMENT ON COLUMN core.export_request.id IS 'Surrogate key.';
COMMENT ON COLUMN core.export_request.app_user_id IS 'User who requested the export.';
COMMENT ON COLUMN core.export_request.learning_link_id IS 'Learning link whose data is exported. NULL when all data of the user is exported.';
COMMENT ON COLUMN core.export_request.requested_at IS 'Moment the export was requested.';
COMMENT ON COLUMN core.export_request.prepare_by IS 'Deadline for preparing the export, no later than one month after the request.';
COMMENT ON COLUMN core.export_request.prepared_at IS 'Moment the export was prepared. NULL while it is being prepared.';
COMMENT ON COLUMN core.export_request.file_location IS 'Address of the export file. NULL until the export is ready.';
COMMENT ON COLUMN core.export_request.available_until IS 'Moment until which the file can be downloaded. NULL until the export is ready.';
--rollback DROP TABLE core.export_request;

--changeset samitava:0011-summary-link
CREATE TABLE core.summary_link (
    id               bigint      GENERATED ALWAYS AS IDENTITY,
    learning_link_id bigint      NOT NULL,
    code             text        NOT NULL,
    created_at       timestamptz NOT NULL,
    valid_until      timestamptz NOT NULL,
    revoked_at       timestamptz,
    CONSTRAINT pk_summary_link PRIMARY KEY (id),
    CONSTRAINT uq_summary_link__code UNIQUE (code),
    CONSTRAINT fk_summary_link__learning_link FOREIGN KEY (learning_link_id)
        REFERENCES core.learning_link (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.summary_link IS 'Read-only link by which a learner shares a summary of own progress.';
COMMENT ON COLUMN core.summary_link.id IS 'Surrogate key.';
COMMENT ON COLUMN core.summary_link.learning_link_id IS 'Learning link whose summary is shared.';
COMMENT ON COLUMN core.summary_link.code IS 'Random value used in the address of the link instead of the id.';
COMMENT ON COLUMN core.summary_link.created_at IS 'Moment the link was created.';
COMMENT ON COLUMN core.summary_link.valid_until IS 'Moment until which the link works. Set by the learner, 14 days from creation by default.';
COMMENT ON COLUMN core.summary_link.revoked_at IS 'Moment the link was revoked. NULL while it is in force.';
--rollback DROP TABLE core.summary_link;

--changeset samitava:0011-feature-toggle
CREATE TABLE core.feature_toggle (
    id               bigint      GENERATED ALWAYS AS IDENTITY,
    feature          text        NOT NULL,
    study_group_id   bigint,
    learning_link_id bigint,
    is_enabled       boolean     NOT NULL,
    changed_at       timestamptz NOT NULL,
    CONSTRAINT pk_feature_toggle PRIMARY KEY (id),
    CONSTRAINT uq_feature_toggle__group_feature UNIQUE (study_group_id, feature),
    CONSTRAINT uq_feature_toggle__link_feature UNIQUE (learning_link_id, feature),
    CONSTRAINT ck_feature_toggle__feature CHECK (feature IN ('adaptation', 'harder_variants', 'oral_error_entry')),
    CONSTRAINT ck_feature_toggle__one_target CHECK (num_nonnulls(study_group_id, learning_link_id) = 1),
    CONSTRAINT fk_feature_toggle__study_group FOREIGN KEY (study_group_id)
        REFERENCES core.study_group (id) ON DELETE CASCADE,
    CONSTRAINT fk_feature_toggle__learning_link FOREIGN KEY (learning_link_id)
        REFERENCES core.learning_link (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.feature_toggle IS 'Feature switched on or off by a teacher for a group or for one learner. A row exists only where the teacher changed the default; the setting of a learner overrides the setting of the group.';
COMMENT ON COLUMN core.feature_toggle.id IS 'Surrogate key.';
COMMENT ON COLUMN core.feature_toggle.feature IS 'Feature: adaptation, harder_variants or oral_error_entry.';
COMMENT ON COLUMN core.feature_toggle.study_group_id IS 'Group the setting applies to. Exactly one of study_group_id and learning_link_id is filled.';
COMMENT ON COLUMN core.feature_toggle.learning_link_id IS 'Learning link the setting applies to: a setting for one learner.';
COMMENT ON COLUMN core.feature_toggle.is_enabled IS 'True when the feature is switched on.';
COMMENT ON COLUMN core.feature_toggle.changed_at IS 'Moment the setting was last changed.';
--rollback DROP TABLE core.feature_toggle;

--changeset samitava:0011-shown-tooltip
CREATE TABLE core.shown_tooltip (
    app_user_id       bigint      NOT NULL,
    interface_element text        NOT NULL,
    shown_at          timestamptz NOT NULL,
    CONSTRAINT pk_shown_tooltip PRIMARY KEY (app_user_id, interface_element),
    CONSTRAINT fk_shown_tooltip__app_user FOREIGN KEY (app_user_id)
        REFERENCES core.app_user (id) ON DELETE CASCADE
);
COMMENT ON TABLE core.shown_tooltip IS 'Onboarding tooltip already shown to a user, so that it is not shown again.';
COMMENT ON COLUMN core.shown_tooltip.app_user_id IS 'User who saw the tooltip.';
COMMENT ON COLUMN core.shown_tooltip.interface_element IS 'Identifier of the interface element. The list of elements is kept in the application code.';
COMMENT ON COLUMN core.shown_tooltip.shown_at IS 'Moment the tooltip was shown.';
--rollback DROP TABLE core.shown_tooltip;
