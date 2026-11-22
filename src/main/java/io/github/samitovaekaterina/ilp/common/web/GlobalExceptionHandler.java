package io.github.samitovaekaterina.ilp.common.web;

import java.util.List;
import org.slf4j.MDC;
import org.springframework.context.MessageSourceResolvable;
import org.springframework.core.MethodParameter;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
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
        if (statusCode.is5xxServerError()) {
            logger.error("Server error", ex);
        }
        ErrorCode errorCode = ErrorCode.forStatus(statusCode);
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

    // Anything unexpected: details go to the log only, the client gets a general message.
    @ExceptionHandler(Exception.class)
    public ResponseEntity<Object> handleUnexpected(Exception ex, WebRequest request) {
        return handleExceptionInternal(ex, null, new HttpHeaders(), ErrorCode.INTERNAL_ERROR.getStatus(), request);
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
