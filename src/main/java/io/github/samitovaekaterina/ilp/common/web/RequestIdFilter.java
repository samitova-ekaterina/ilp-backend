package io.github.samitovaekaterina.ilp.common.web;

import java.io.IOException;
import java.util.UUID;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestIdFilter extends OncePerRequestFilter {

	public static final String HEADER = "X-Request-Id";

	public static final String MDC_KEY = "http.request.id";

	private static final Logger log = LoggerFactory.getLogger(RequestIdFilter.class);

	@Override
	protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
			throws ServletException, IOException {
		// Always our own value: a number sent by the client could put any text into the log.
		String requestId = UUID.randomUUID().toString();
		long startedAt = System.nanoTime();
		MDC.put(MDC_KEY, requestId);
		response.setHeader(HEADER, requestId);
		try {
			chain.doFilter(request, response);
		}
		finally {
			long nanos = System.nanoTime() - startedAt;
			log.atInfo()
				.addKeyValue("http.request.method", request.getMethod())
				.addKeyValue("url.path", request.getRequestURI())
				.addKeyValue("http.response.status_code", response.getStatus())
				.addKeyValue("event.duration", nanos)
				.log("{} {} -> {} in {} ms", request.getMethod(), request.getRequestURI(), response.getStatus(),
						nanos / 1_000_000);
			// Tomcat reuses threads: without this the next request would start with the old number.
			MDC.remove(MDC_KEY);
		}
	}

}
