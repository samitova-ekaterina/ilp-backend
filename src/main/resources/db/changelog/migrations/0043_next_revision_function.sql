--liquibase formatted sql

--changeset samitava:0043-next-revision-function splitStatements:false
-- The four ratings and their numbers follow the Anki defaults (SM-2 variant).
-- After a correct answer the interval grows by at least one day, otherwise a short interval
-- multiplied by 1.2 would round back to itself.
CREATE FUNCTION core.next_revision(p_interval_days integer, p_ease numeric, p_rating text)
RETURNS TABLE (new_interval_days integer, new_ease numeric)
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_interval_days IS NULL OR p_interval_days < 1 OR p_ease IS NULL OR p_ease < 1.30 THEN
        RAISE EXCEPTION 'next_revision: interval must be at least 1 and ease at least 1.30, got % and %', p_interval_days, p_ease;
    END IF;
    CASE p_rating
        WHEN 'error' THEN
            new_interval_days := 1;
            new_ease := greatest(1.30, p_ease - 0.20);
        WHEN 'slow_and_changed' THEN
            new_interval_days := greatest(p_interval_days + 1, round(p_interval_days * 1.2)::integer);
            new_ease := greatest(1.30, p_ease - 0.15);
        WHEN 'moderate' THEN
            new_interval_days := greatest(p_interval_days + 1, round(p_interval_days * p_ease)::integer);
            new_ease := p_ease;
        WHEN 'fast' THEN
            new_interval_days := greatest(p_interval_days + 1, round(p_interval_days * p_ease * 1.3)::integer);
            new_ease := p_ease + 0.15;
        ELSE
            RAISE EXCEPTION 'next_revision: unknown rating %', p_rating;
    END CASE;
    RETURN NEXT;
END
$$;
--rollback DROP FUNCTION core.next_revision(integer, numeric, text);

--changeset samitava:0043-next-revision-function-comment
COMMENT ON FUNCTION core.next_revision(integer, numeric, text) IS 'New interval in days and new ease of a revision record after an answer with the given rating: error, slow_and_changed, moderate or fast.';
--rollback COMMENT ON FUNCTION core.next_revision(integer, numeric, text) IS NULL;
