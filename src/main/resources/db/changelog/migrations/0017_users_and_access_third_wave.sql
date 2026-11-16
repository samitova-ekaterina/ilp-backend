--liquibase formatted sql

--changeset samitava:0017-app-user-style-and-glossaries
ALTER TABLE core.app_user
    ADD COLUMN visual_style_id       bigint,
    ADD COLUMN show_added_glossaries boolean NOT NULL DEFAULT true,
    ADD CONSTRAINT fk_app_user__visual_style FOREIGN KEY (visual_style_id)
        REFERENCES core.visual_style (id) ON DELETE SET NULL;
COMMENT ON COLUMN core.app_user.visual_style_id IS 'Visual style chosen by the user. NULL when the default style is used.';
COMMENT ON COLUMN core.app_user.show_added_glossaries IS 'Whether glossaries added to the material are shown to the user.';
--rollback ALTER TABLE core.app_user DROP COLUMN show_added_glossaries, DROP COLUMN visual_style_id;
