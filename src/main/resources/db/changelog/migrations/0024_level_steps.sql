--liquibase formatted sql

--changeset samitava:0024-level-step-data
INSERT INTO core.level_step (name, sort_order, cefr_level_id)
SELECT l.name, l.sort_order, l.id
FROM core.cefr_level l
WHERE l.name IN ('A1', 'A2', 'B1', 'B2', 'C1', 'C2');
--rollback DELETE FROM core.level_step WHERE name IN ('A1', 'A2', 'B1', 'B2', 'C1', 'C2');
