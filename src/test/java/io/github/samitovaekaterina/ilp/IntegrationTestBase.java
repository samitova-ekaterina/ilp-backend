package io.github.samitovaekaterina.ilp;

import io.github.samitovaekaterina.ilp.mail.TestMailConfiguration;
import org.junit.jupiter.api.Tag;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

/** The parent of every test that needs the assembled application and a real PostgreSQL. */
@Tag("integration")
@SpringBootTest
@AutoConfigureMockMvc
@Import(TestMailConfiguration.class)
public abstract class IntegrationTestBase {

    private static TestDatabase database;
    private static String applicationPassword;

    @DynamicPropertySource
    static void connectToTheContainer(DynamicPropertyRegistry registry) {
        TestDatabase started = database();
        registry.add("spring.datasource.url", started::jdbcUrl);
        registry.add("spring.datasource.password", () -> applicationPassword);
        registry.add("spring.liquibase.password", started::ownerPassword);
    }

    /** For a test that prepares reference data: the account of the application may not change it. */
    protected static JdbcTemplate asOwner() {
        return new JdbcTemplate(database().ownerDataSource());
    }

    // One database for the whole run: starting PostgreSQL for every test class would take most of the time.
    private static synchronized TestDatabase database() {
        if (database == null) {
            database = TestDatabase.start();
            applicationPassword = database.createApplicationAccount();
        }
        return database;
    }
}
