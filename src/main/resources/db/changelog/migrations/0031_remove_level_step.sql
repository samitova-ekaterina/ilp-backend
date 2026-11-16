--liquibase formatted sql

--changeset samitava:0031-step-columns-to-cefr-level
-- A level step turned out to be the same thing as a CEFR level: six steps, same names, same order.
-- The six columns that pointed to a step now point to the level, and the step table is removed.
ALTER TABLE core.scale_level
    DROP CONSTRAINT fk_scale_level__entry_level_step,
    DROP CONSTRAINT fk_scale_level__current_level_step;
UPDATE core.scale_level sl
   SET entry_level_step_id   = (SELECT ls.cefr_level_id FROM core.level_step ls WHERE ls.id = sl.entry_level_step_id),
       current_level_step_id = (SELECT ls.cefr_level_id FROM core.level_step ls WHERE ls.id = sl.current_level_step_id);
ALTER TABLE core.scale_level RENAME COLUMN entry_level_step_id TO entry_cefr_level_id;
ALTER TABLE core.scale_level RENAME COLUMN current_level_step_id TO current_cefr_level_id;
ALTER TABLE core.scale_level
    ADD CONSTRAINT fk_scale_level__entry_cefr_level FOREIGN KEY (entry_cefr_level_id)
        REFERENCES core.cefr_level (id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_scale_level__current_cefr_level FOREIGN KEY (current_cefr_level_id)
        REFERENCES core.cefr_level (id) ON DELETE RESTRICT;
COMMENT ON COLUMN core.scale_level.entry_cefr_level_id IS 'Level at the start of learning. NULL until set.';
COMMENT ON COLUMN core.scale_level.current_cefr_level_id IS 'Current level. NULL while there is no data; shown as no data.';

ALTER TABLE core.level_change
    DROP CONSTRAINT fk_level_change__previous_level_step,
    DROP CONSTRAINT fk_level_change__new_level_step;
UPDATE core.level_change lc
   SET previous_level_step_id = (SELECT ls.cefr_level_id FROM core.level_step ls WHERE ls.id = lc.previous_level_step_id),
       new_level_step_id      = (SELECT ls.cefr_level_id FROM core.level_step ls WHERE ls.id = lc.new_level_step_id);
ALTER TABLE core.level_change RENAME COLUMN previous_level_step_id TO previous_cefr_level_id;
ALTER TABLE core.level_change RENAME COLUMN new_level_step_id TO new_cefr_level_id;
ALTER TABLE core.level_change RENAME CONSTRAINT ck_level_change__steps_differ TO ck_level_change__levels_differ;
ALTER TABLE core.level_change
    ADD CONSTRAINT fk_level_change__previous_cefr_level FOREIGN KEY (previous_cefr_level_id)
        REFERENCES core.cefr_level (id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_level_change__new_cefr_level FOREIGN KEY (new_cefr_level_id)
        REFERENCES core.cefr_level (id) ON DELETE RESTRICT;
COMMENT ON COLUMN core.level_change.previous_cefr_level_id IS 'Level before the change.';
COMMENT ON COLUMN core.level_change.new_cefr_level_id IS 'Level after the change. Differs from the previous level.';

ALTER TABLE core.competition DROP CONSTRAINT fk_competition__level_step;
UPDATE core.competition c
   SET level_step_id = (SELECT ls.cefr_level_id FROM core.level_step ls WHERE ls.id = c.level_step_id);
ALTER TABLE core.competition RENAME COLUMN level_step_id TO cefr_level_id;
ALTER TABLE core.competition
    ADD CONSTRAINT fk_competition__cefr_level FOREIGN KEY (cefr_level_id)
        REFERENCES core.cefr_level (id) ON DELETE RESTRICT;
COMMENT ON COLUMN core.competition.cefr_level_id IS 'Level of the participants. Only outside a lesson; NULL for a competition composed by a teacher.';

ALTER TABLE stats.statistics_event DROP CONSTRAINT fk_statistics_event__level_step;
UPDATE stats.statistics_event se
   SET level_step_id = (SELECT ls.cefr_level_id FROM core.level_step ls WHERE ls.id = se.level_step_id);
ALTER TABLE stats.statistics_event RENAME COLUMN level_step_id TO cefr_level_id;
ALTER TABLE stats.statistics_event
    ADD CONSTRAINT fk_statistics_event__cefr_level FOREIGN KEY (cefr_level_id)
        REFERENCES core.cefr_level (id) ON DELETE RESTRICT;
COMMENT ON COLUMN stats.statistics_event.cefr_level_id IS 'Level of the learner on that scale at the moment of the event.';
--rollback ALTER TABLE stats.statistics_event DROP CONSTRAINT fk_statistics_event__cefr_level;
--rollback UPDATE stats.statistics_event se SET cefr_level_id = (SELECT ls.id FROM core.level_step ls WHERE ls.cefr_level_id = se.cefr_level_id);
--rollback ALTER TABLE stats.statistics_event RENAME COLUMN cefr_level_id TO level_step_id;
--rollback ALTER TABLE stats.statistics_event ADD CONSTRAINT fk_statistics_event__level_step FOREIGN KEY (level_step_id) REFERENCES core.level_step (id) ON DELETE RESTRICT;
--rollback COMMENT ON COLUMN stats.statistics_event.level_step_id IS 'Step of the learner on that scale at the moment of the event.';
--rollback ALTER TABLE core.competition DROP CONSTRAINT fk_competition__cefr_level;
--rollback UPDATE core.competition c SET cefr_level_id = (SELECT ls.id FROM core.level_step ls WHERE ls.cefr_level_id = c.cefr_level_id);
--rollback ALTER TABLE core.competition RENAME COLUMN cefr_level_id TO level_step_id;
--rollback ALTER TABLE core.competition ADD CONSTRAINT fk_competition__level_step FOREIGN KEY (level_step_id) REFERENCES core.level_step (id) ON DELETE RESTRICT;
--rollback COMMENT ON COLUMN core.competition.level_step_id IS 'Level step of the participants. Only outside a lesson; NULL for a competition composed by a teacher.';
--rollback ALTER TABLE core.level_change DROP CONSTRAINT fk_level_change__previous_cefr_level, DROP CONSTRAINT fk_level_change__new_cefr_level;
--rollback UPDATE core.level_change lc SET previous_cefr_level_id = (SELECT ls.id FROM core.level_step ls WHERE ls.cefr_level_id = lc.previous_cefr_level_id), new_cefr_level_id = (SELECT ls.id FROM core.level_step ls WHERE ls.cefr_level_id = lc.new_cefr_level_id);
--rollback ALTER TABLE core.level_change RENAME COLUMN previous_cefr_level_id TO previous_level_step_id;
--rollback ALTER TABLE core.level_change RENAME COLUMN new_cefr_level_id TO new_level_step_id;
--rollback ALTER TABLE core.level_change RENAME CONSTRAINT ck_level_change__levels_differ TO ck_level_change__steps_differ;
--rollback ALTER TABLE core.level_change ADD CONSTRAINT fk_level_change__previous_level_step FOREIGN KEY (previous_level_step_id) REFERENCES core.level_step (id) ON DELETE RESTRICT, ADD CONSTRAINT fk_level_change__new_level_step FOREIGN KEY (new_level_step_id) REFERENCES core.level_step (id) ON DELETE RESTRICT;
--rollback COMMENT ON COLUMN core.level_change.previous_level_step_id IS 'Step before the change.';
--rollback COMMENT ON COLUMN core.level_change.new_level_step_id IS 'Step after the change. Differs from the previous step.';
--rollback ALTER TABLE core.scale_level DROP CONSTRAINT fk_scale_level__entry_cefr_level, DROP CONSTRAINT fk_scale_level__current_cefr_level;
--rollback UPDATE core.scale_level sl SET entry_cefr_level_id = (SELECT ls.id FROM core.level_step ls WHERE ls.cefr_level_id = sl.entry_cefr_level_id), current_cefr_level_id = (SELECT ls.id FROM core.level_step ls WHERE ls.cefr_level_id = sl.current_cefr_level_id);
--rollback ALTER TABLE core.scale_level RENAME COLUMN entry_cefr_level_id TO entry_level_step_id;
--rollback ALTER TABLE core.scale_level RENAME COLUMN current_cefr_level_id TO current_level_step_id;
--rollback ALTER TABLE core.scale_level ADD CONSTRAINT fk_scale_level__entry_level_step FOREIGN KEY (entry_level_step_id) REFERENCES core.level_step (id) ON DELETE RESTRICT, ADD CONSTRAINT fk_scale_level__current_level_step FOREIGN KEY (current_level_step_id) REFERENCES core.level_step (id) ON DELETE RESTRICT;
--rollback COMMENT ON COLUMN core.scale_level.entry_level_step_id IS 'Step at the start of learning. NULL until set.';
--rollback COMMENT ON COLUMN core.scale_level.current_level_step_id IS 'Current step. NULL while there is no data; shown as no data.';

--changeset samitava:0031-drop-level-step
DROP TABLE core.level_step;
--rollback CREATE TABLE core.level_step (
--rollback     id            bigint  GENERATED ALWAYS AS IDENTITY,
--rollback     name          text    NOT NULL,
--rollback     sort_order    integer NOT NULL,
--rollback     cefr_level_id bigint  NOT NULL,
--rollback     CONSTRAINT pk_level_step PRIMARY KEY (id),
--rollback     CONSTRAINT uq_level_step__name UNIQUE (name),
--rollback     CONSTRAINT uq_level_step__sort_order UNIQUE (sort_order),
--rollback     CONSTRAINT fk_level_step__cefr_level FOREIGN KEY (cefr_level_id)
--rollback         REFERENCES core.cefr_level (id) ON DELETE RESTRICT
--rollback );
--rollback COMMENT ON TABLE core.level_step IS 'Step inside a CEFR level. Levels are measured in steps finer than CEFR.';
--rollback COMMENT ON COLUMN core.level_step.id IS 'Surrogate key.';
--rollback COMMENT ON COLUMN core.level_step.name IS 'Step name.';
--rollback COMMENT ON COLUMN core.level_step.sort_order IS 'Ordinal number across all steps. Defines the next step.';
--rollback COMMENT ON COLUMN core.level_step.cefr_level_id IS 'CEFR level the step belongs to.';
--rollback INSERT INTO core.level_step (name, sort_order, cefr_level_id) SELECT name, sort_order, id FROM core.cefr_level ORDER BY sort_order;
--rollback GRANT SELECT ON core.level_step TO ilp_read, ilp_write;
