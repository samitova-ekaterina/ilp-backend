package io.github.samitovaekaterina.ilp.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import io.github.samitovaekaterina.ilp.IntegrationTestBase;
import java.time.Duration;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.session.Session;
import org.springframework.session.SessionRepository;
import org.springframework.session.jdbc.JdbcIndexedSessionRepository;

class SessionStoreIT extends IntegrationTestBase {

    private static final Duration THIRTY_DAYS = Duration.ofDays(30);

    @Autowired
    private SessionRepository<? extends Session> sessions;

    @Autowired
    private JdbcIndexedSessionRepository sessionCleanUp;

    @AfterEach
    void removeTheSessions() {
        asOwner().update("DELETE FROM core.spring_session");
    }

    @Test
    void aSessionLiesInTheDatabaseAndIsReadBackFromIt() {
        String sessionId = storeASession(sessions, "remembered", "a value");

        assertThat(rowsOf(sessionId)).isEqualTo(1);
        // The store keeps nothing in memory, so this value has come from the database.
        Session readBack = sessions.findById(sessionId);
        assertThat(readBack).isNotNull();
        assertThat(readBack.<String>getAttribute("remembered")).isEqualTo("a value");
    }

    @Test
    void aSessionIsKeptForThirtyDays() {
        String sessionId = storeASession(sessions, "remembered", "a value");

        Integer seconds = asOwner()
                .queryForObject(
                        "SELECT max_inactive_interval FROM core.spring_session WHERE session_id = ?",
                        Integer.class,
                        sessionId);
        assertThat(Duration.ofSeconds(seconds)).isEqualTo(THIRTY_DAYS);
    }

    @Test
    void anExpiredSessionIsRemovedWithWhatItRemembered() {
        String sessionId = storeASession(sessions, "remembered", "a value");
        asOwner().update("UPDATE core.spring_session SET expiry_time = 0 WHERE session_id = ?", sessionId);

        sessionCleanUp.cleanUpExpiredSessions();

        assertThat(rowsOf(sessionId)).isZero();
        Integer rememberedValues =
                asOwner().queryForObject("SELECT count(*) FROM core.spring_session_attributes", Integer.class);
        assertThat(rememberedValues).isZero();
    }

    private static <S extends Session> String storeASession(
            SessionRepository<S> repository, String name, String value) {
        S session = repository.createSession();
        session.setAttribute(name, value);
        repository.save(session);
        return session.getId();
    }

    private Integer rowsOf(String sessionId) {
        return asOwner()
                .queryForObject(
                        "SELECT count(*) FROM core.spring_session WHERE session_id = ?", Integer.class, sessionId);
    }
}
