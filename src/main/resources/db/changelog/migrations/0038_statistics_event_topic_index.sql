--liquibase formatted sql

--changeset samitava:0038-statistics-event-topic-index
-- Missed in 0030: topic is a working table, and deleting a topic looks up its statistics events.
CREATE INDEX ix_statistics_event__topic ON stats.statistics_event (topic_id);
--rollback DROP INDEX stats.ix_statistics_event__topic;
