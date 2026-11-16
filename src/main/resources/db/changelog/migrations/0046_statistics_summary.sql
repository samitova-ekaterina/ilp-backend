--liquibase formatted sql

--changeset samitava:0046-statistics-summary
-- Reports read the summary, not the event table: the event table only grows.
CREATE MATERIALIZED VIEW stats.mv_statistics_summary AS
SELECT date_trunc('month', se.event_date)::date AS month,
       se.exercise_type_id,
       se.scale_id,
       se.cefr_level_id,
       count(*)                                        AS events,
       count(*) FILTER (WHERE se.is_correct)           AS correct_events,
       count(*) FILTER (WHERE se.attempt_number = 1)   AS first_attempts,
       count(*) FILTER (WHERE se.time_bucket = 'fast') AS fast_events,
       count(*) FILTER (WHERE se.time_bucket = 'slow') AS slow_events,
       count(DISTINCT se.link_code)                    AS learning_links
  FROM stats.statistics_event se
 GROUP BY date_trunc('month', se.event_date)::date, se.exercise_type_id, se.scale_id, se.cefr_level_id;
-- Required by REFRESH ... CONCURRENTLY, which does not block readers.
CREATE UNIQUE INDEX uq_mv_statistics_summary__key
    ON stats.mv_statistics_summary (month, exercise_type_id, scale_id, cefr_level_id);
COMMENT ON MATERIALIZED VIEW stats.mv_statistics_summary IS 'Anonymous statistics by month, exercise type, scale and level. Refreshed with stats.refresh_statistics_summary().';
GRANT SELECT ON stats.mv_statistics_summary TO ilp_read, ilp_write;
--rollback DROP MATERIALIZED VIEW stats.mv_statistics_summary;

--changeset samitava:0046-refresh-statistics-summary splitStatements:false
-- Only the owner may refresh a materialized view, so the refresh is wrapped for the application role.
CREATE PROCEDURE stats.refresh_statistics_summary()
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY stats.mv_statistics_summary;
END
$$;
--rollback DROP PROCEDURE stats.refresh_statistics_summary();

--changeset samitava:0046-refresh-statistics-summary-privileges
COMMENT ON PROCEDURE stats.refresh_statistics_summary() IS 'Refreshes stats.mv_statistics_summary without blocking readers.';
REVOKE ALL ON PROCEDURE stats.refresh_statistics_summary() FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE stats.refresh_statistics_summary() TO ilp_write, ilp_admin;
--rollback REVOKE ALL ON PROCEDURE stats.refresh_statistics_summary() FROM ilp_write, ilp_admin;
