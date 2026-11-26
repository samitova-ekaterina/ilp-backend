package io.github.samitovaekaterina.ilp.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Clock;
import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.mock.web.MockHttpSession;

class SessionLifetimeFilterTest {

    private static final Duration LIFETIME = Duration.ofDays(30);

    @Test
    void aSessionOlderThanItsLifetimeIsEnded() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        MockHttpSession session = (MockHttpSession) request.getSession();
        MockFilterChain chain = new MockFilterChain();

        filterAfter(Duration.ofDays(31)).doFilter(request, new MockHttpServletResponse(), chain);

        assertThat(session.isInvalid()).isTrue();
        assertThat(chain.getRequest()).isSameAs(request);
    }

    @Test
    void aSessionWithinItsLifetimeGoesOn() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        MockHttpSession session = (MockHttpSession) request.getSession();
        MockFilterChain chain = new MockFilterChain();

        filterAfter(Duration.ofDays(29)).doFilter(request, new MockHttpServletResponse(), chain);

        assertThat(session.isInvalid()).isFalse();
        assertThat(chain.getRequest()).isSameAs(request);
    }

    @Test
    void aRequestWithoutASessionGetsNone() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        MockFilterChain chain = new MockFilterChain();

        filterAfter(Duration.ofDays(31)).doFilter(request, new MockHttpServletResponse(), chain);

        assertThat(request.getSession(false)).isNull();
        assertThat(chain.getRequest()).isSameAs(request);
    }

    // The session is created now, so the filter is given a clock that already shows a later day.
    private static SessionLifetimeFilter filterAfter(Duration passed) {
        return new SessionLifetimeFilter(LIFETIME, Clock.offset(Clock.systemUTC(), passed));
    }
}
