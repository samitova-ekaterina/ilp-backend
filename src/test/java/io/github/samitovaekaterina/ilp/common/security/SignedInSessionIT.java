package io.github.samitovaekaterina.ilp.common.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import io.github.samitovaekaterina.ilp.IntegrationTestBase;
import jakarta.servlet.http.Cookie;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Base64;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextImpl;
import org.springframework.security.web.context.HttpSessionSecurityContextRepository;
import org.springframework.session.Session;
import org.springframework.session.SessionRepository;
import org.springframework.test.web.servlet.MockMvc;

class SignedInSessionIT extends IntegrationTestBase {

    // Closed and without a controller: a signed-in user gets 404 here, anyone else 401.
    private static final String CLOSED_ADDRESS = "/api/v1/nothing";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private SessionRepository<? extends Session> sessions;

    @AfterEach
    void removeTheSessions() {
        asOwner().update("DELETE FROM core.spring_session");
    }

    @Test
    void theNextRequestKnowsTheUserByTheSessionInTheDatabase() throws Exception {
        String sessionId = storeASessionOfASignedInUser(sessions);

        mockMvc.perform(get(CLOSED_ADDRESS).cookie(cookieOf(sessionId))).andExpect(status().isNotFound());

        String signedInAs = asOwner()
                .queryForObject(
                        "SELECT principal_name FROM core.spring_session WHERE session_id = ?", String.class, sessionId);
        assertThat(signedInAs).isEqualTo("1");
    }

    @Test
    void aRequestWithAnUnknownSessionIsRefused() throws Exception {
        mockMvc.perform(get(CLOSED_ADDRESS).cookie(cookieOf("00000000-0000-0000-0000-000000000000")))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void aSessionOlderThanThirtyDaysIsEndedEvenIfItWasJustUsed() throws Exception {
        String sessionId = storeASessionOfASignedInUser(sessions);
        makeOlder(sessionId, Duration.ofDays(31));

        mockMvc.perform(get(CLOSED_ADDRESS).cookie(cookieOf(sessionId))).andExpect(status().isUnauthorized());

        assertThat(rowsOf(sessionId)).isZero();
    }

    @Test
    void aSessionYoungerThanThirtyDaysGoesOn() throws Exception {
        String sessionId = storeASessionOfASignedInUser(sessions);
        makeOlder(sessionId, Duration.ofDays(29));

        mockMvc.perform(get(CLOSED_ADDRESS).cookie(cookieOf(sessionId))).andExpect(status().isNotFound());

        assertThat(rowsOf(sessionId)).isEqualTo(1);
    }

    @Test
    void aRefusalDoesNotCreateASession() throws Exception {
        mockMvc.perform(get(CLOSED_ADDRESS)).andExpect(status().isUnauthorized());

        Integer rows = asOwner().queryForObject("SELECT count(*) FROM core.spring_session", Integer.class);
        assertThat(rows).isZero();
    }

    // Signing in appears with the sign-in request; until then the test writes the session the way sign-in will.
    private static <S extends Session> String storeASessionOfASignedInUser(SessionRepository<S> repository) {
        S session = repository.createSession();
        session.setAttribute(
                HttpSessionSecurityContextRepository.SPRING_SECURITY_CONTEXT_KEY,
                new SecurityContextImpl(UsernamePasswordAuthenticationToken.authenticated("1", null, List.of())));
        repository.save(session);
        return session.getId();
    }

    private static Cookie cookieOf(String sessionId) {
        // The session cookie carries the id in Base64, this is how Spring Session writes it.
        return new Cookie("SESSION", Base64.getEncoder().encodeToString(sessionId.getBytes(StandardCharsets.UTF_8)));
    }

    private void makeOlder(String sessionId, Duration age) {
        asOwner()
                .update(
                        "UPDATE core.spring_session SET creation_time = creation_time - ? WHERE session_id = ?",
                        age.toMillis(),
                        sessionId);
    }

    private Integer rowsOf(String sessionId) {
        return asOwner()
                .queryForObject(
                        "SELECT count(*) FROM core.spring_session WHERE session_id = ?", Integer.class, sessionId);
    }
}
