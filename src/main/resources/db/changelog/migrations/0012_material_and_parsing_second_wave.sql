--liquibase formatted sql

--changeset samitava:0012-folder
CREATE TABLE core.folder (
    id               bigint GENERATED ALWAYS AS IDENTITY,
    owner_user_id    bigint NOT NULL,
    name             text   NOT NULL,
    parent_folder_id bigint,
    folder_kind      text   NOT NULL,
    split_method     text,
    CONSTRAINT pk_folder PRIMARY KEY (id),
    CONSTRAINT ck_folder__folder_kind CHECK (folder_kind IN ('ordinary', 'book')),
    CONSTRAINT ck_folder__split_method CHECK (split_method IN ('by_contents', 'by_headings', 'by_equal_ranges')),
    CONSTRAINT ck_folder__split_only_for_book CHECK (split_method IS NULL OR folder_kind = 'book'),
    CONSTRAINT fk_folder__owner_user FOREIGN KEY (owner_user_id)
        REFERENCES core.app_user (id) ON DELETE CASCADE,
    CONSTRAINT fk_folder__parent_folder FOREIGN KEY (parent_folder_id)
        REFERENCES core.folder (id) ON DELETE RESTRICT
);
COMMENT ON TABLE core.folder IS 'Folder of the material library. A folder of kind book holds the parts of one large document.';
COMMENT ON COLUMN core.folder.id IS 'Surrogate key.';
COMMENT ON COLUMN core.folder.owner_user_id IS 'User who owns the folder.';
COMMENT ON COLUMN core.folder.name IS 'Folder name.';
COMMENT ON COLUMN core.folder.parent_folder_id IS 'Folder that contains this one. NULL for a top-level folder.';
COMMENT ON COLUMN core.folder.folder_kind IS 'Kind: ordinary or book.';
COMMENT ON COLUMN core.folder.split_method IS 'How the document was split into parts: by_contents, by_headings or by_equal_ranges. Filled only for a book, NULL for an ordinary folder.';
--rollback DROP TABLE core.folder;

--changeset samitava:0012-material-folder-and-parts
ALTER TABLE core.material
    ADD COLUMN folder_id        bigint,
    ADD COLUMN part_number      integer,
    ADD COLUMN source_page_from integer,
    ADD COLUMN source_page_to   integer,
    ADD COLUMN archived_at      timestamptz,
    ADD CONSTRAINT ck_material__part_number_positive CHECK (part_number > 0),
    ADD CONSTRAINT ck_material__source_pages CHECK (
        (source_page_from IS NULL AND source_page_to IS NULL)
        OR (source_page_from IS NOT NULL AND source_page_to IS NOT NULL AND source_page_from <= source_page_to)
    ),
    ADD CONSTRAINT fk_material__folder FOREIGN KEY (folder_id)
        REFERENCES core.folder (id) ON DELETE RESTRICT;
CREATE UNIQUE INDEX uq_material__folder_part
    ON core.material (folder_id, part_number)
    WHERE part_number IS NOT NULL;
COMMENT ON COLUMN core.material.folder_id IS 'Folder the material lies in. NULL when it lies outside folders.';
COMMENT ON COLUMN core.material.part_number IS 'Number of the part inside a book. NULL for an ordinary material.';
COMMENT ON COLUMN core.material.source_page_from IS 'First page of the part in the source document. NULL for an ordinary material.';
COMMENT ON COLUMN core.material.source_page_to IS 'Last page of the part in the source document. NULL for an ordinary material.';
COMMENT ON COLUMN core.material.archived_at IS 'Moment the material was moved to the archive. NULL while it is in the library.';
--rollback DROP INDEX core.uq_material__folder_part;
--rollback ALTER TABLE core.material DROP COLUMN archived_at, DROP COLUMN source_page_to, DROP COLUMN source_page_from, DROP COLUMN part_number, DROP COLUMN folder_id;

--changeset samitava:0012-exercise-source-and-archive
ALTER TABLE core.exercise
    ADD COLUMN source_exercise_id bigint,
    ADD COLUMN archived_at        timestamptz,
    ADD CONSTRAINT fk_exercise__source_exercise FOREIGN KEY (source_exercise_id)
        REFERENCES core.exercise (id) ON DELETE SET NULL;
COMMENT ON COLUMN core.exercise.source_exercise_id IS 'Exercise this one was converted from. NULL for an exercise that was not converted.';
COMMENT ON COLUMN core.exercise.archived_at IS 'Moment the exercise was moved to the archive. NULL while it is in the library.';
--rollback ALTER TABLE core.exercise DROP COLUMN archived_at, DROP COLUMN source_exercise_id;

--changeset samitava:0012-flag-placement
ALTER TABLE core.flag
    ADD COLUMN placed_by_user_id bigint,
    ADD COLUMN placed_at         timestamptz NOT NULL,
    ADD COLUMN closed_at         timestamptz,
    ADD CONSTRAINT fk_flag__placed_by_user FOREIGN KEY (placed_by_user_id)
        REFERENCES core.app_user (id) ON DELETE SET NULL;
COMMENT ON COLUMN core.flag.placed_by_user_id IS 'User who placed the flag. NULL when the system placed it during parsing.';
COMMENT ON COLUMN core.flag.placed_at IS 'Moment the flag was placed.';
COMMENT ON COLUMN core.flag.closed_at IS 'Moment the flag was closed. NULL while it is pending.';
--rollback ALTER TABLE core.flag DROP COLUMN closed_at, DROP COLUMN placed_at, DROP COLUMN placed_by_user_id;
