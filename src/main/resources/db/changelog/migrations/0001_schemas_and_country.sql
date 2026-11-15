--liquibase formatted sql

--changeset samitava:0001-schemas
CREATE SCHEMA core;
CREATE SCHEMA stats;
COMMENT ON SCHEMA core IS 'Main application data.';
COMMENT ON SCHEMA stats IS 'Anonymised usage statistics. Contains no personal data.';
--rollback DROP SCHEMA stats;
--rollback DROP SCHEMA core;

--changeset samitava:0001-country
CREATE TABLE core.country (
    id          bigint  GENERATED ALWAYS AS IDENTITY,
    name        text    NOT NULL,
    code        text    NOT NULL,
    consent_age integer NOT NULL,
    CONSTRAINT pk_country PRIMARY KEY (id),
    CONSTRAINT uq_country__code UNIQUE (code),
    CONSTRAINT ck_country__code_format CHECK (code ~ '^[A-Z]{2}$'),
    CONSTRAINT ck_country__consent_age_positive CHECK (consent_age > 0)
);
COMMENT ON TABLE core.country IS 'Country of residence of a user. Defines the age of consent.';
COMMENT ON COLUMN core.country.id IS 'Surrogate key.';
COMMENT ON COLUMN core.country.name IS 'Country name.';
COMMENT ON COLUMN core.country.code IS 'Two-letter country code, ISO 3166-1 alpha-2.';
COMMENT ON COLUMN core.country.consent_age IS 'Age from which a user can give consent to data processing in this country.';
--rollback DROP TABLE core.country;
