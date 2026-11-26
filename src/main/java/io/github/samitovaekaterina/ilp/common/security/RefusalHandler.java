package io.github.samitovaekaterina.ilp.common.security;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerExceptionResolver;

/** Passes the refusals of Spring Security to the common error handler, so that every error has the same body. */
@Component
public class RefusalHandler implements AuthenticationEntryPoint, AccessDeniedHandler {

    private final HandlerExceptionResolver exceptionResolver;

    // Spring MVC has several resolvers; this name is the one that knows the common error handler.
    public RefusalHandler(@Qualifier("handlerExceptionResolver") HandlerExceptionResolver exceptionResolver) {
        this.exceptionResolver = exceptionResolver;
    }

    @Override
    public void commence(HttpServletRequest request, HttpServletResponse response, AuthenticationException refusal) {
        exceptionResolver.resolveException(request, response, null, refusal);
    }

    @Override
    public void handle(HttpServletRequest request, HttpServletResponse response, AccessDeniedException refusal) {
        exceptionResolver.resolveException(request, response, null, refusal);
    }
}
