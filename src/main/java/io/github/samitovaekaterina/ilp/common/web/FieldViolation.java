package io.github.samitovaekaterina.ilp.common.web;

import java.util.Locale;

import org.springframework.context.MessageSourceResolvable;

public record FieldViolation(String field, String code) {

	// The value typed by the user is left out on purpose: it may be a password.
	static FieldViolation of(String field, MessageSourceResolvable error) {
		String[] codes = error.getCodes();
		String constraint = (codes != null && codes.length > 0) ? codes[codes.length - 1] : "invalid";
		return new FieldViolation(field, constraint.replaceAll("([a-z])([A-Z])", "$1-$2").toLowerCase(Locale.ROOT));
	}

}
