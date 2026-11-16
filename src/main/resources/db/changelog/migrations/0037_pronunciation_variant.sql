--liquibase formatted sql

--changeset samitava:0037-pronunciation-variant
-- The learner chooses a pronunciation variant, and transcription and audio depend on it.
CREATE TABLE core.pronunciation_variant (
    id          bigint GENERATED ALWAYS AS IDENTITY,
    language_id bigint NOT NULL,
    code        text   NOT NULL,
    name        text   NOT NULL,
    CONSTRAINT pk_pronunciation_variant PRIMARY KEY (id),
    CONSTRAINT uq_pronunciation_variant__code UNIQUE (code),
    CONSTRAINT uq_pronunciation_variant__language_name UNIQUE (language_id, name),
    -- Target of the composite foreign keys that keep a variant inside its own language.
    CONSTRAINT uq_pronunciation_variant__id_and_language UNIQUE (id, language_id),
    CONSTRAINT ck_pronunciation_variant__code_format CHECK (code ~ '^[a-z]{2}-[A-Z]{2}$'),
    CONSTRAINT fk_pronunciation_variant__language FOREIGN KEY (language_id)
        REFERENCES core.language (id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.pronunciation_variant IS 'Pronunciation variant of a language, for example British and American English. Reference table.';
COMMENT ON COLUMN core.pronunciation_variant.id IS 'Surrogate key.';
COMMENT ON COLUMN core.pronunciation_variant.language_id IS 'Language the variant belongs to.';
COMMENT ON COLUMN core.pronunciation_variant.code IS 'Language and region code, for example en-GB.';
COMMENT ON COLUMN core.pronunciation_variant.name IS 'Variant name.';
--rollback DROP TABLE core.pronunciation_variant;

--changeset samitava:0037-pronunciation-variant-data
INSERT INTO core.pronunciation_variant (language_id, code, name)
SELECT l.id, v.code, v.name
  FROM (VALUES ('en', 'en-GB', 'British English'),
               ('en', 'en-US', 'American English'),
               ('ru', 'ru-RU', 'Russian')) AS v (language_code, code, name)
  JOIN core.language l ON l.code = v.language_code;
--rollback DELETE FROM core.pronunciation_variant WHERE code IN ('en-GB', 'en-US', 'ru-RU');

--changeset samitava:0037-pronunciation-choice
CREATE TABLE core.pronunciation_choice (
    id                       bigint GENERATED ALWAYS AS IDENTITY,
    learner_user_id          bigint NOT NULL,
    language_id              bigint NOT NULL,
    pronunciation_variant_id bigint NOT NULL,
    CONSTRAINT pk_pronunciation_choice PRIMARY KEY (id),
    CONSTRAINT uq_pronunciation_choice__learner_language UNIQUE (learner_user_id, language_id),
    CONSTRAINT fk_pronunciation_choice__learner_user FOREIGN KEY (learner_user_id)
        REFERENCES core.app_user (id) ON DELETE CASCADE,
    CONSTRAINT fk_pronunciation_choice__variant FOREIGN KEY (pronunciation_variant_id, language_id)
        REFERENCES core.pronunciation_variant (id, language_id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.pronunciation_choice IS 'Pronunciation variant chosen by a learner for a language. Belongs to the learner, not to a learning link: the choice is the same with every teacher.';
COMMENT ON COLUMN core.pronunciation_choice.id IS 'Surrogate key.';
COMMENT ON COLUMN core.pronunciation_choice.learner_user_id IS 'Learner who made the choice.';
COMMENT ON COLUMN core.pronunciation_choice.language_id IS 'Language the choice is made for. Repeats the language of the variant so that one choice per language can be enforced.';
COMMENT ON COLUMN core.pronunciation_choice.pronunciation_variant_id IS 'Chosen variant.';
--rollback DROP TABLE core.pronunciation_choice;

--changeset samitava:0037-word-pronunciation
ALTER TABLE core.word ADD CONSTRAINT uq_word__id_and_language UNIQUE (id, language_id);
CREATE TABLE core.word_pronunciation (
    id                       bigint GENERATED ALWAYS AS IDENTITY,
    word_id                  bigint NOT NULL,
    language_id              bigint NOT NULL,
    pronunciation_variant_id bigint NOT NULL,
    transcription            text,
    audio_location           text,
    audio_requested_at       timestamptz,
    CONSTRAINT pk_word_pronunciation PRIMARY KEY (id),
    CONSTRAINT uq_word_pronunciation__word_variant UNIQUE (word_id, pronunciation_variant_id),
    -- Both keys carry the language, so a word cannot get a variant of another language.
    CONSTRAINT fk_word_pronunciation__word FOREIGN KEY (word_id, language_id)
        REFERENCES core.word (id, language_id) ON DELETE CASCADE,
    CONSTRAINT fk_word_pronunciation__variant FOREIGN KEY (pronunciation_variant_id, language_id)
        REFERENCES core.pronunciation_variant (id, language_id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.word_pronunciation IS 'Transcription and audio of a word in one pronunciation variant.';
COMMENT ON COLUMN core.word_pronunciation.id IS 'Surrogate key.';
COMMENT ON COLUMN core.word_pronunciation.word_id IS 'Word.';
COMMENT ON COLUMN core.word_pronunciation.language_id IS 'Language of the word and of the variant. Repeats both so that they cannot differ.';
COMMENT ON COLUMN core.word_pronunciation.pronunciation_variant_id IS 'Pronunciation variant.';
COMMENT ON COLUMN core.word_pronunciation.transcription IS 'Transcription from a dictionary. NULL when the dictionary has no exact match.';
COMMENT ON COLUMN core.word_pronunciation.audio_location IS 'Address of the audio file. NULL until the audio exists.';
COMMENT ON COLUMN core.word_pronunciation.audio_requested_at IS 'Moment the audio was requested. NULL when it was never requested.';
--rollback DROP TABLE core.word_pronunciation;
--rollback ALTER TABLE core.word DROP CONSTRAINT uq_word__id_and_language;

--changeset samitava:0037-move-word-pronunciation
-- What was stored on the word had no variant. English goes to the British variant: the test materials follow a British textbook.
INSERT INTO core.word_pronunciation (word_id, language_id, pronunciation_variant_id, transcription, audio_location, audio_requested_at)
SELECT w.id, w.language_id, v.id, w.transcription, w.audio_location, w.audio_requested_at
  FROM core.word w
  JOIN core.pronunciation_variant v ON v.language_id = w.language_id AND v.code IN ('en-GB', 'ru-RU')
 WHERE w.transcription IS NOT NULL OR w.audio_location IS NOT NULL OR w.audio_requested_at IS NOT NULL;
ALTER TABLE core.word
    DROP COLUMN transcription,
    DROP COLUMN audio_location,
    DROP COLUMN audio_requested_at;
--rollback ALTER TABLE core.word ADD COLUMN transcription text, ADD COLUMN audio_location text, ADD COLUMN audio_requested_at timestamptz;
--rollback COMMENT ON COLUMN core.word.transcription IS 'Transcription from a dictionary. NULL when the dictionary has no exact match.';
--rollback COMMENT ON COLUMN core.word.audio_location IS 'Address of the audio file. NULL until the audio exists.';
--rollback COMMENT ON COLUMN core.word.audio_requested_at IS 'Moment the audio was requested. NULL when it was never requested.';
--rollback UPDATE core.word w SET transcription = wp.transcription, audio_location = wp.audio_location, audio_requested_at = wp.audio_requested_at FROM core.word_pronunciation wp JOIN core.pronunciation_variant v ON v.id = wp.pronunciation_variant_id WHERE wp.word_id = w.id AND v.code IN ('en-GB', 'ru-RU');
--rollback DELETE FROM core.word_pronunciation;

--changeset samitava:0037-pronunciation-privileges
GRANT SELECT ON core.pronunciation_variant, core.pronunciation_choice, core.word_pronunciation TO ilp_read, ilp_write;
GRANT INSERT, UPDATE, DELETE ON core.pronunciation_choice, core.word_pronunciation TO ilp_write;
--rollback REVOKE ALL ON core.pronunciation_variant, core.pronunciation_choice, core.word_pronunciation FROM ilp_read, ilp_write;
