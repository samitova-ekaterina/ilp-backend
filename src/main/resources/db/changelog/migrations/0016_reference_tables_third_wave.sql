--liquibase formatted sql

--changeset samitava:0016-visual-style
CREATE TABLE core.visual_style (
    id                        bigint  GENERATED ALWAYS AS IDENTITY,
    code                      text    NOT NULL,
    name                      text    NOT NULL,
    display_order             integer NOT NULL,
    unlock_cefr_level_id      bigint,
    unlock_closed_scale_count integer,
    CONSTRAINT pk_visual_style PRIMARY KEY (id),
    CONSTRAINT uq_visual_style__code UNIQUE (code),
    CONSTRAINT uq_visual_style__name UNIQUE (name),
    CONSTRAINT uq_visual_style__display_order UNIQUE (display_order),
    CONSTRAINT ck_visual_style__unlock_complete CHECK ((unlock_cefr_level_id IS NULL) = (unlock_closed_scale_count IS NULL)),
    CONSTRAINT ck_visual_style__unlock_scale_count_range CHECK (unlock_closed_scale_count BETWEEN 1 AND 4),
    CONSTRAINT fk_visual_style__unlock_cefr_level FOREIGN KEY (unlock_cefr_level_id)
        REFERENCES core.cefr_level (id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.visual_style IS 'Visual style of the interface. Some styles are available to everyone, others are unlocked as a reward for closed scales.';
COMMENT ON COLUMN core.visual_style.id IS 'Surrogate key.';
COMMENT ON COLUMN core.visual_style.code IS 'Stable identifier used by the application. Never changed or translated.';
COMMENT ON COLUMN core.visual_style.name IS 'Style name shown to users.';
COMMENT ON COLUMN core.visual_style.display_order IS 'Position of the style in the list.';
COMMENT ON COLUMN core.visual_style.unlock_cefr_level_id IS 'CEFR level at which the style is unlocked. NULL for a style available to everyone.';
COMMENT ON COLUMN core.visual_style.unlock_closed_scale_count IS 'Number of scales, from 1 to 4, the learner must have closed at that level to unlock the style. NULL for a style available to everyone.';
--rollback DROP TABLE core.visual_style;
