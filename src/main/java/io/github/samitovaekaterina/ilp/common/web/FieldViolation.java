package io.github.samitovaekaterina.ilp.common.web;

import java.util.Locale;

import org.springframework.validation.FieldError;

public record FieldViolation(String field, String code) {

	// The value typed by the user is left out on purpose: it may be a password.
	static FieldViolation of(FieldError error) {
		String constraint = (error.getCode() != null) ? error.getCode() : "invalid";
		return new FieldViolation(error.getField(),
				constraint.replaceAll("([a-z])([A-Z])", "$1-$2").toLowerCase(Locale.ROOT));
	}

}
