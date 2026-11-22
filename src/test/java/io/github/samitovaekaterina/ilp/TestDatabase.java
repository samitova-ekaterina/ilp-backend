package io.github.samitovaekaterina.ilp;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.UUID;
import javax.sql.DataSource;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.testcontainers.containers.JdbcDatabaseContainer;
import org.testcontainers.postgresql.PostgreSQLContainer;

/** An empty PostgreSQL in a container, prepared the way the README tells an administrator to prepare it. */
final class TestDatabase {

    private static final String IMAGE = "postgres:17.5";
    private static final String OWNER = "ilp_owner";
    private static final String APPLICATION = "ilp_app";

    private final JdbcDatabaseContainer<?> container;
    private final String ownerPassword;

    private TestDatabase(JdbcDatabaseContainer<?> container, String ownerPassword) {
        this.container = container;
        this.ownerPassword = ownerPassword;
    }

    static TestDatabase start() {
        JdbcDatabaseContainer<?> container = new PostgreSQLContainer(IMAGE);
        container.start();
        TestDatabase database = new TestDatabase(container, randomPassword());
        database.asAdministrator(
                "CREATE ROLE " + OWNER + " LOGIN CREATEROLE PASSWORD '" + database.ownerPassword + "'",
                "CREATE DATABASE ilp OWNER " + OWNER + " ENCODING 'UTF8' TEMPLATE template0");
        return database;
    }

    /** Creates the account of the application and returns its password. */
    String createApplicationAccount() {
        String password = randomPassword();
        // The application starts before the migrations run, so its role must exist earlier than they create it.
        asAdministrator(
                "CREATE ROLE ilp_write NOLOGIN",
                "CREATE ROLE " + APPLICATION + " LOGIN PASSWORD '" + password + "'",
                "GRANT ilp_write TO " + APPLICATION);
        return password;
    }

    String jdbcUrl() {
        return "jdbc:postgresql://" + container.getHost() + ":" + container.getFirstMappedPort() + "/ilp";
    }

    String ownerPassword() {
        return ownerPassword;
    }

    DataSource ownerDataSource() {
        return new DriverManagerDataSource(jdbcUrl(), OWNER, ownerPassword);
    }

    private void asAdministrator(String... statements) {
        try (Connection connection = DriverManager.getConnection(
                        container.getJdbcUrl(), container.getUsername(), container.getPassword());
                Statement statement = connection.createStatement()) {
            for (String sql : statements) {
                statement.execute(sql);
            }
        } catch (SQLException e) {
            throw new IllegalStateException("The test database could not be prepared", e);
        }
    }

    // A new password for every run: no password of a database account is ever written in the repository.
    private static String randomPassword() {
        return UUID.randomUUID().toString();
    }
}
