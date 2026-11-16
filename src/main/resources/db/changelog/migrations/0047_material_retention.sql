--liquibase formatted sql

--changeset samitava:0047-material-retention
-- When a teacher erases the account, learners keep the materials they worked with for a limited time,
-- so that their history does not vanish without warning. Such a material has no owner and a date of deletion.
ALTER TABLE core.material ALTER COLUMN owner_user_id DROP NOT NULL;
ALTER TABLE core.material ADD COLUMN retained_until date;
ALTER TABLE core.material ADD CONSTRAINT ck_material__ownerless_is_retained
    CHECK ((owner_user_id IS NULL) = (retained_until IS NOT NULL));
COMMENT ON COLUMN core.material.owner_user_id IS 'Owner of the material. NULL when the owner erased the account and the material is kept for the learners until retained_until.';
COMMENT ON COLUMN core.material.retained_until IS 'Last day the material of an erased owner is kept for the learners who worked with it. NULL for a material with an owner.';
-- The daily clean-up looks only at the few materials that wait for deletion.
CREATE INDEX ix_material__retained_until ON core.material (retained_until) WHERE retained_until IS NOT NULL;
--rollback DROP INDEX core.ix_material__retained_until;
--rollback DELETE FROM core.material WHERE owner_user_id IS NULL;
--rollback ALTER TABLE core.material DROP CONSTRAINT ck_material__ownerless_is_retained;
--rollback ALTER TABLE core.material DROP COLUMN retained_until;
--rollback ALTER TABLE core.material ALTER COLUMN owner_user_id SET NOT NULL;
--rollback COMMENT ON COLUMN core.material.owner_user_id IS 'User who uploaded the material.';

--changeset samitava:0047-erasure-request-retention-days
ALTER TABLE core.erasure_request ADD COLUMN material_retention_days integer;
ALTER TABLE core.erasure_request ADD CONSTRAINT ck_erasure_request__material_retention_days_range
    CHECK (material_retention_days BETWEEN 0 AND 365);
COMMENT ON COLUMN core.erasure_request.material_retention_days IS 'For how many days the materials stay available to the learners after the account is erased, from 0 to 365. Chosen by the user; NULL means the default of 7 days.';
GRANT SELECT (material_retention_days) ON core.erasure_request TO ilp_read;
--rollback ALTER TABLE core.erasure_request DROP COLUMN material_retention_days;
