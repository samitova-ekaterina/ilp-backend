package io.github.samitovaekaterina.ilp.common.web;

import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;

public enum ErrorCode {

	BAD_REQUEST(HttpStatus.BAD_REQUEST, "common.bad-request", "The request cannot be processed as it was sent."),
	NOT_FOUND(HttpStatus.NOT_FOUND, "common.not-found", "The requested address does not exist."),
	METHOD_NOT_ALLOWED(HttpStatus.METHOD_NOT_ALLOWED, "common.method-not-allowed",
			"The method is not supported for this address."),
	UNSUPPORTED_MEDIA_TYPE(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "common.unsupported-media-type",
			"The type of the sent data is not supported."),
	INTERNAL_ERROR(HttpStatus.INTERNAL_SERVER_ERROR, "common.internal-error",
			"An unexpected error occurred on the server.");

	private final HttpStatus status;

	private final String code;

	private final String detail;

	ErrorCode(HttpStatus status, String code, String detail) {
		this.status = status;
		this.code = code;
		this.detail = detail;
	}

	public HttpStatus getStatus() {
		return status;
	}

	public String getCode() {
		return code;
	}

	public String getDetail() {
		return detail;
	}

	// Any other 4xx counts as a bad request, any other 5xx as a server error.
	public static ErrorCode forStatus(HttpStatusCode status) {
		for (ErrorCode errorCode : values()) {
			if (errorCode.status.value() == status.value()) {
				return errorCode;
			}
		}
		return status.is5xxServerError() ? INTERNAL_ERROR : BAD_REQUEST;
	}

}
