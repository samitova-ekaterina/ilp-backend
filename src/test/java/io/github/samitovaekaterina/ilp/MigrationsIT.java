package io.github.samitovaekaterina.ilp;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import javax.sql.DataSource;
import liquibase.exception.LiquibaseException;
import liquibase.integration.spring.SpringLiquibase;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.DefaultResourceLoader;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.jdbc.core.JdbcTemplate;

@Tag("integration")
class MigrationsIT {

    private static final String CHANGELOG = "classpath:db/changelog/db.changelog-master.yaml";
    private static final String MIGRATION_FILES = "classpath:db/changelog/migrations/*.sql";

    private static DataSource owner;

    @BeforeAll
    static void applyAllMigrationsToAnEmptyDatabase() throws LiquibaseException {
        // Its own database: the other tests share one that already has the migrations.
        owner = TestDatabase.start().ownerDataSource();
        applyMigrations();
    }

    @Test
    void everyChangeSetWrittenInTheMigrationFilesIsApplied() throws IOException {
        assertThat(appliedChangeSets()).isEqualTo(changeSetsInTheFiles());
    }

    @Test
    void aSecondRunAppliesNothing() throws LiquibaseException {
        int before = appliedChangeSets();

        applyMigrations();

        assertThat(appliedChangeSets()).isEqualTo(before);
    }

    private static void applyMigrations() throws LiquibaseException {
        SpringLiquibase liquibase = new SpringLiquibase();
        liquibase.setDataSource(owner);
        liquibase.setChangeLog(CHANGELOG);
        liquibase.setResourceLoader(new DefaultResourceLoader());
        liquibase.afterPropertiesSet();
    }

    private static int appliedChangeSets() {
        return new JdbcTemplate(owner).queryForObject("SELECT count(*) FROM databasechangelog", Integer.class);
    }

    private static int changeSetsInTheFiles() throws IOException {
        int count = 0;
        for (Resource file : new PathMatchingResourcePatternResolver().getResources(MIGRATION_FILES)) {
            count += (int) file.getContentAsString(StandardCharsets.UTF_8)
                    .lines()
                    .filter(line -> line.startsWith("--changeset"))
                    .count();
        }
        return count;
    }
}
