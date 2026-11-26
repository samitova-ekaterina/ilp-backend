package io.github.samitovaekaterina.ilp.common.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import org.springframework.web.filter.OncePerRequestFilter;

/** Ends a session when its whole life is over, however recently it was used. */
final class SessionLifetimeFilter extends OncePerRequestFilter {

    private final Duration lifetime;

    private final Clock clock;

    SessionLifetimeFilter(Duration lifetime, Clock clock) {
        this.lifetime = lifetime;
        this.clock = clock;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        // The session store alone would not do it: it counts the time from the last request.
        HttpSession session = request.getSession(false);
        if (session != null && livedLongerThanAllowed(session)) {
            session.invalidate();
        }
        chain.doFilter(request, response);
    }

    private boolean livedLongerThanAllowed(HttpSession session) {
        Instant created = Instant.ofEpochMilli(session.getCreationTime());
        return created.plus(lifetime).isBefore(clock.instant());
    }
}
