--liquibase formatted sql

--changeset samitava:0051-spring-session
-- Columns are named and typed as the library Spring Session requires, constraints and indexes as this database does.
CREATE TABLE core.spring_session (
    primary_id            char(36)     NOT NULL,
    session_id            char(36)     NOT NULL,
    creation_time         bigint       NOT NULL,
    last_access_time      bigint       NOT NULL,
    max_inactive_interval integer      NOT NULL,
    expiry_time           bigint       NOT NULL,
    principal_name        varchar(100),
    CONSTRAINT pk_spring_session PRIMARY KEY (primary_id),
    CONSTRAINT uq_spring_session__session_id UNIQUE (session_id)
);
-- Expired sessions are found by this column when they are removed.
CREATE INDEX ix_spring_session__expiry_time ON core.spring_session (expiry_time);
-- All sessions of one user are found by this column, for example to close them when the password changes.
CREATE INDEX ix_spring_session__principal_name ON core.spring_session (principal_name);
COMMENT ON TABLE core.spring_session IS 'Session of a signed-in user. Service table of the library Spring Session: the application code does not query it directly.';
COMMENT ON COLUMN core.spring_session.primary_id IS 'Key of the row. Stays the same when the session id changes.';
COMMENT ON COLUMN core.spring_session.session_id IS 'Session id that the browser holds in its cookie. Replaced at sign-in.';
COMMENT ON COLUMN core.spring_session.creation_time IS 'Moment the session was created, in milliseconds since 1970-01-01 UTC.';
COMMENT ON COLUMN core.spring_session.last_access_time IS 'Moment of the last request in the session, in milliseconds since 1970-01-01 UTC.';
COMMENT ON COLUMN core.spring_session.max_inactive_interval IS 'Number of seconds without requests after which the session expires.';
COMMENT ON COLUMN core.spring_session.expiry_time IS 'Moment the session expires, in milliseconds since 1970-01-01 UTC.';
COMMENT ON COLUMN core.spring_session.principal_name IS 'Name under which the user is signed in. NULL for a session without sign-in.';
--rollback DROP TABLE core.spring_session;

--changeset samitava:0051-spring-session-attributes
CREATE TABLE core.spring_session_attributes (
    session_primary_id char(36)     NOT NULL,
    attribute_name     varchar(200) NOT NULL,
    attribute_bytes    bytea        NOT NULL,
    CONSTRAINT pk_spring_session_attributes PRIMARY KEY (session_primary_id, attribute_name),
    CONSTRAINT fk_spring_session_attributes__spring_session FOREIGN KEY (session_primary_id)
        REFERENCES core.spring_session (primary_id) ON DELETE CASCADE
);
COMMENT ON TABLE core.spring_session_attributes IS 'What a session remembers: one row per named value. Service table of the library Spring Session.';
COMMENT ON COLUMN core.spring_session_attributes.session_primary_id IS 'Session the value belongs to.';
COMMENT ON COLUMN core.spring_session_attributes.attribute_name IS 'Name of the value.';
COMMENT ON COLUMN core.spring_session_attributes.attribute_bytes IS 'The value as the library serialized it. For a signed-in user it holds who is signed in.';
--rollback DROP TABLE core.spring_session_attributes;

--changeset samitava:0051-spring-session-privileges
-- Only the application works with sessions. The reading role gets nothing: a session tells who is signed in.
GRANT SELECT, INSERT, UPDATE, DELETE ON core.spring_session, core.spring_session_attributes TO ilp_write;
--rollback REVOKE ALL ON core.spring_session, core.spring_session_attributes FROM ilp_write;
