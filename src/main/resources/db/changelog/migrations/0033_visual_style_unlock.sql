--liquibase formatted sql

--changeset samitava:0033-visual-style-unlock-without-level
-- A reward style opens by the number of closed scales only. Tying it to a level as well
-- would take rewards away from a learner who starts at a high level.
ALTER TABLE core.visual_style DROP CONSTRAINT ck_visual_style__unlock_complete;
ALTER TABLE core.visual_style DROP COLUMN unlock_cefr_level_id;
COMMENT ON COLUMN core.visual_style.unlock_closed_scale_count IS 'Number of scales, from 1 to 4, the learner must have closed to unlock the style. NULL for a style available to everyone.';
--rollback ALTER TABLE core.visual_style ADD COLUMN unlock_cefr_level_id bigint;
--rollback ALTER TABLE core.visual_style ADD CONSTRAINT fk_visual_style__unlock_cefr_level FOREIGN KEY (unlock_cefr_level_id) REFERENCES core.cefr_level (id) ON DELETE RESTRICT;
--rollback ALTER TABLE core.visual_style ADD CONSTRAINT ck_visual_style__unlock_complete CHECK ((unlock_cefr_level_id IS NULL) = (unlock_closed_scale_count IS NULL)) NOT VALID;
--rollback COMMENT ON COLUMN core.visual_style.unlock_closed_scale_count IS 'Number of scales, from 1 to 4, the learner must have closed at that level to unlock the style. NULL for a style available to everyone.';
--rollback COMMENT ON COLUMN core.visual_style.unlock_cefr_level_id IS 'CEFR level at which the style is unlocked. NULL for a style available to everyone.';
