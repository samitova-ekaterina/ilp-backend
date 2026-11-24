package io.github.samitovaekaterina.ilp.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import io.github.samitovaekaterina.ilp.IntegrationTestBase;
import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.session.web.http.CookieSerializer;

// With a started server: without one Spring Boot takes the cookie settings from the servlet container instead.
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SessionCookieIT extends IntegrationTestBase {

    private static final Duration THIRTY_DAYS = Duration.ofDays(30);

    @Autowired
    private CookieSerializer cookieSerializer;

    @Test
    void theSessionCookieLivesThirtyDaysAndIsNotSentFromOtherSites() {
        MockHttpServletResponse response = new MockHttpServletResponse();

        cookieSerializer.writeCookieValue(
                new CookieSerializer.CookieValue(new MockHttpServletRequest(), response, "any-session"));

        assertThat(response.getHeader("Set-Cookie"))
                .contains("Max-Age=" + THIRTY_DAYS.toSeconds())
                .contains("SameSite=Strict")
                .contains("Secure")
                .contains("HttpOnly");
    }
}
