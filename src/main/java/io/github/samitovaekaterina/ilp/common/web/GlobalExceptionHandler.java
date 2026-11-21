package io.github.samitovaekaterina.ilp.common.web;

import org.slf4j.MDC;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

@RestControllerAdvice
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

	// Every standard Spring MVC error passes through here and gets the same body.
	@Override
	protected ResponseEntity<Object> handleExceptionInternal(Exception ex, Object body, HttpHeaders headers,
			HttpStatusCode statusCode, WebRequest request) {
		ErrorCode errorCode = ErrorCode.forStatus(statusCode);
		ProblemDetail problem = ProblemDetail.forStatusAndDetail(statusCode, errorCode.getDetail());
		problem.setProperty("code", errorCode.getCode());
		String requestId = MDC.get(RequestIdFilter.MDC_KEY);
		if (requestId != null) {
			problem.setProperty("requestId", requestId);
		}
		return super.handleExceptionInternal(ex, problem, headers, statusCode, request);
	}

	// Anything unexpected: details go to the log only, the client gets a general message.
	@ExceptionHandler(Exception.class)
	public ResponseEntity<Object> handleUnexpected(Exception ex, WebRequest request) {
		logger.error("Unexpected error", ex);
		return handleExceptionInternal(ex, null, new HttpHeaders(), ErrorCode.INTERNAL_ERROR.getStatus(), request);
	}

}
