--liquibase formatted sql

--changeset samitava:0020-flag-reason-data
INSERT INTO core.flag_reason (code, name) VALUES
    ('example_instead_of_answer', 'Example instead of an answer'),
    ('multiple_answers',          'Several acceptable answers'),
    ('text_in_image',             'Text inside an image'),
    ('no_text_layer',             'No text layer'),
    ('depends_on_previous',       'Depends on a previous exercise'),
    ('key_not_matched',           'Key answer not matched'),
    ('type_not_recognized',       'Type not recognised'),
    ('enter_manually',            'Enter manually'),
    ('reported_as_wrong',         'Reported as wrong');
--rollback DELETE FROM core.flag_reason WHERE code IN ('example_instead_of_answer', 'multiple_answers', 'text_in_image', 'no_text_layer', 'depends_on_previous', 'key_not_matched', 'type_not_recognized', 'enter_manually', 'reported_as_wrong');

--changeset samitava:0020-error-type-data
INSERT INTO core.error_type (code, name) VALUES
    ('spelling',      'Spelling'),
    ('form',          'Form'),
    ('word_choice',   'Word choice'),
    ('comprehension', 'Comprehension');
--rollback DELETE FROM core.error_type WHERE code IN ('spelling', 'form', 'word_choice', 'comprehension');

--changeset samitava:0020-visual-style-data
INSERT INTO core.visual_style (code, name, display_order) VALUES
    ('default', 'Default', 1);
--rollback DELETE FROM core.visual_style WHERE code = 'default';
