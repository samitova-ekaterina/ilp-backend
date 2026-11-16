--liquibase formatted sql

--changeset samitava:0022-exercise-type-compatibility-data
INSERT INTO core.exercise_type_compatibility (source_type_id, target_type_id, is_harder)
SELECT s.id, t.id, p.is_harder
FROM (VALUES
    ('gap_bank', 'gap_bank_typed', true),
    ('gap_bank_typed', 'gap_no_bank', true),
    ('gap_bank', 'gap_no_bank', true),
    ('gap_bank_typed', 'gap_bank', false),
    ('gap_no_bank', 'gap_bank_typed', false),
    ('gap_no_bank', 'gap_bank', false),
    ('image_labels_bank', 'image_labels_bank_typed', true),
    ('image_labels_bank_typed', 'image_labels_no_bank', true),
    ('image_labels_bank', 'image_labels_no_bank', true),
    ('image_labels_bank_typed', 'image_labels_bank', false),
    ('image_labels_no_bank', 'image_labels_bank_typed', false),
    ('image_labels_no_bank', 'image_labels_bank', false),
    ('grouping', 'grouping_typed', true),
    ('grouping_typed', 'word_list', true),
    ('grouping', 'word_list', true),
    ('grouping_typed', 'grouping', false),
    ('word_list', 'grouping_typed', false),
    ('word_list', 'grouping', false),
    ('replace_marked', 'find_and_correct', true),
    ('find_and_correct', 'replace_marked', false),
    ('single_choice', 'single_choice_typed', true),
    ('single_choice_typed', 'word', true),
    ('single_choice', 'word', true),
    ('single_choice_typed', 'single_choice', false),
    ('inline_choice', 'inline_choice_typed', true),
    ('inline_choice_typed', 'gap_no_bank', true),
    ('inline_choice', 'gap_no_bank', true),
    ('inline_choice_typed', 'inline_choice', false),
    ('multiple_choice', 'multiple_choice_typed', true),
    ('multiple_choice_typed', 'word_list', true),
    ('multiple_choice', 'word_list', true),
    ('multiple_choice_typed', 'multiple_choice', false),
    ('matching', 'matching_typed', true),
    ('matching_typed', 'word', true),
    ('matching', 'word', true),
    ('matching_typed', 'matching', false),
    ('crossword', 'word', true)
) AS p (source_code, target_code, is_harder)
JOIN core.exercise_type s ON s.code = p.source_code
JOIN core.exercise_type t ON t.code = p.target_code;
--rollback DELETE FROM core.exercise_type_compatibility;
