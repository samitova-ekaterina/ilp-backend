package io.github.samitovaekaterina.ilp;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import javax.sql.DataSource;
import liquibase.Liquibase;
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
        List<Map<String, Object>> before = executionRecords();

        applyMigrations();

        assertThat(executionRecords()).isEqualTo(before);
    }

    @Test
    void theLastMigrationRollsBackAndAppliesAgain() throws IOException, LiquibaseException {
        int all = changeSetsInTheFiles();
        int last = changeSetsIn(lastMigrationFile());
        try {
            rollBackTheLastChangeSets(last);

            assertThat(appliedChangeSets()).isEqualTo(all - last);
        } finally {
            // The other tests of this class expect the database with every migration applied.
            applyMigrations();
        }
        assertThat(appliedChangeSets()).isEqualTo(all);
    }

    private static void applyMigrations() throws LiquibaseException {
        run(new SpringLiquibase());
    }

    private static void rollBackTheLastChangeSets(int count) throws LiquibaseException {
        // The same preparation as for applying, so that Liquibase recognises the change sets it has applied.
        run(new SpringLiquibase() {
            @Override
            protected void performUpdate(Liquibase prepared) throws LiquibaseException {
                prepared.rollback(count, "");
            }
        });
    }

    private static void run(SpringLiquibase liquibase) throws LiquibaseException {
        liquibase.setDataSource(owner);
        liquibase.setChangeLog(CHANGELOG);
        liquibase.setResourceLoader(new DefaultResourceLoader());
        liquibase.afterPropertiesSet();
    }

    private static int appliedChangeSets() {
        return new JdbcTemplate(owner).queryForObject("SELECT count(*) FROM databasechangelog", Integer.class);
    }

    // The whole record of every change set, not their number: a change set that runs again keeps its row.
    private static List<Map<String, Object>> executionRecords() {
        return new JdbcTemplate(owner)
                .queryForList(
                        "SELECT id, author, filename, dateexecuted, orderexecuted, exectype, md5sum, deployment_id"
                                + " FROM databasechangelog ORDER BY orderexecuted, id");
    }

    private static int changeSetsInTheFiles() throws IOException {
        int count = 0;
        for (Resource file : migrationFiles()) {
            count += changeSetsIn(file);
        }
        return count;
    }

    private static int changeSetsIn(Resource file) throws IOException {
        return (int) file.getContentAsString(StandardCharsets.UTF_8)
                .lines()
                .filter(line -> line.startsWith("--changeset"))
                .count();
    }

    private static Resource lastMigrationFile() throws IOException {
        // The file names start with the number of the migration, so the last by name is the last applied.
        return Arrays.stream(migrationFiles())
                .max(Comparator.comparing(Resource::getFilename))
                .orElseThrow();
    }

    private static Resource[] migrationFiles() throws IOException {
        return new PathMatchingResourcePatternResolver().getResources(MIGRATION_FILES);
    }
}
