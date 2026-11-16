--liquibase formatted sql

--changeset samitava:0019-country-data
INSERT INTO core.country (name, code, consent_age) VALUES
    ('Lithuania', 'LT', 14);
--rollback DELETE FROM core.country WHERE code = 'LT';

--changeset samitava:0019-language-data
INSERT INTO core.language (code, name) VALUES
    ('en', 'English'),
    ('ru', 'Russian');
--rollback DELETE FROM core.language WHERE code IN ('en', 'ru');

--changeset samitava:0019-scale-data
INSERT INTO core.scale (code, name, display_order) VALUES
    ('vocabulary', 'Vocabulary', 1),
    ('grammar',    'Grammar',    2),
    ('writing',    'Writing',    3),
    ('speech',     'Speech',     4);
--rollback DELETE FROM core.scale WHERE code IN ('vocabulary', 'grammar', 'writing', 'speech');

--changeset samitava:0019-cefr-level-data
INSERT INTO core.cefr_level (name, sort_order) VALUES
    ('A1', 1),
    ('A2', 2),
    ('B1', 3),
    ('B2', 4),
    ('C1', 5),
    ('C2', 6);
--rollback DELETE FROM core.cefr_level WHERE name IN ('A1', 'A2', 'B1', 'B2', 'C1', 'C2');
