package io.github.samitovaekaterina.ilp.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.InsufficientAuthenticationException;

class RefusalHandlerTest {

    private final List<Object> passedOn = new ArrayList<>();

    private final RefusalHandler handler = new RefusalHandler((gotRequest, gotResponse, controller, refusal) -> {
        passedOn.add(gotRequest);
        passedOn.add(gotResponse);
        passedOn.add(refusal);
        return null;
    });

    private final MockHttpServletRequest request = new MockHttpServletRequest();

    private final MockHttpServletResponse response = new MockHttpServletResponse();

    @Test
    void theRefusalOfAVisitorWhoIsNotSignedInGoesToTheCommonErrorHandler() {
        InsufficientAuthenticationException refusal = new InsufficientAuthenticationException("not signed in");

        handler.commence(request, response, refusal);

        assertThat(passedOn).containsExactly(request, response, refusal);
    }

    @Test
    void theRefusalOfAnActionGoesToTheCommonErrorHandler() {
        AccessDeniedException refusal = new AccessDeniedException("not allowed");

        handler.handle(request, response, refusal);

        assertThat(passedOn).containsExactly(request, response, refusal);
    }
}
