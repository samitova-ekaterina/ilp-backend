package io.github.samitovaekaterina.ilp.common.web;

import java.util.List;
import org.slf4j.MDC;
import org.springframework.context.MessageSourceResolvable;
import org.springframework.core.MethodParameter;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.csrf.CsrfException;
import org.springframework.validation.FieldError;
import org.springframework.validation.method.ParameterValidationResult;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.method.annotation.HandlerMethodValidationException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

@RestControllerAdvice
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    // Every standard Spring MVC error passes through here and gets the same body.
    @Override
    protected ResponseEntity<Object> handleExceptionInternal(
            Exception ex, Object body, HttpHeaders headers, HttpStatusCode statusCode, WebRequest request) {
        return respond(ex, ErrorCode.forStatus(statusCode), headers, statusCode, request);
    }

    // Anything unexpected: details go to the log only, the client gets a general message.
    @ExceptionHandler(Exception.class)
    public ResponseEntity<Object> handleUnexpected(Exception ex, WebRequest request) {
        return respond(ex, ErrorCode.INTERNAL_ERROR, request);
    }

    // The refusals of Spring Security arrive here through RefusalHandler: they are raised before any controller.
    @ExceptionHandler(AuthenticationException.class)
    public ResponseEntity<Object> handleNotSignedIn(AuthenticationException ex, WebRequest request) {
        return respond(ex, ErrorCode.UNAUTHENTICATED, request);
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<Object> handleNotAllowed(AccessDeniedException ex, WebRequest request) {
        return respond(ex, ex instanceof CsrfException ? ErrorCode.CSRF : ErrorCode.FORBIDDEN, request);
    }

    private ResponseEntity<Object> respond(Exception ex, ErrorCode errorCode, WebRequest request) {
        return respond(ex, errorCode, new HttpHeaders(), errorCode.getStatus(), request);
    }

    private ResponseEntity<Object> respond(
            Exception ex, ErrorCode errorCode, HttpHeaders headers, HttpStatusCode statusCode, WebRequest request) {
        if (statusCode.is5xxServerError()) {
            logger.error("Server error", ex);
        }
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(statusCode, errorCode.getDetail());
        problem.setProperty("code", errorCode.getCode());
        String requestId = MDC.get(RequestIdFilter.MDC_KEY);
        if (requestId != null) {
            problem.setProperty("requestId", requestId);
        }
        List<FieldViolation> violations = violations(ex);
        if (!violations.isEmpty()) {
            problem.setProperty("errors", violations);
        }
        return super.handleExceptionInternal(ex, problem, headers, statusCode, request);
    }

    private static List<FieldViolation> violations(Exception ex) {
        if (ex instanceof MethodArgumentNotValidException invalid) {
            return invalid.getBindingResult().getFieldErrors().stream()
                    .map(error -> FieldViolation.of(error.getField(), error))
                    .toList();
        }
        if (ex instanceof HandlerMethodValidationException invalid && !invalid.isForReturnValue()) {
            return invalid.getParameterValidationResults().stream()
                    .flatMap(result -> result.getResolvableErrors().stream()
                            .map(error -> FieldViolation.of(fieldName(result, error), error)))
                    .toList();
        }
        if (ex instanceof MethodArgumentTypeMismatchException mismatch) {
            return List.of(new FieldViolation(mismatch.getName(), "type-mismatch"));
        }
        if (ex instanceof MissingServletRequestParameterException missing) {
            return List.of(new FieldViolation(missing.getParameterName(), "missing"));
        }
        return List.of();
    }

    // The name the client used in the address, not the name of the variable in the code.
    private static String fieldName(ParameterValidationResult result, MessageSourceResolvable error) {
        if (error instanceof FieldError fieldError) {
            return fieldError.getField();
        }
        MethodParameter parameter = result.getMethodParameter();
        RequestParam requestParam = parameter.getParameterAnnotation(RequestParam.class);
        if (requestParam != null && !requestParam.name().isEmpty()) {
            return requestParam.name();
        }
        PathVariable pathVariable = parameter.getParameterAnnotation(PathVariable.class);
        if (pathVariable != null && !pathVariable.name().isEmpty()) {
            return pathVariable.name();
        }
        return parameter.getParameterName();
    }
}
