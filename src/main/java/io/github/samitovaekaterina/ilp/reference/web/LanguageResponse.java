package io.github.samitovaekaterina.ilp.reference.web;

import io.github.samitovaekaterina.ilp.reference.model.Language;

public record LanguageResponse(String code, String name) {

	static LanguageResponse from(Language language) {
		return new LanguageResponse(language.getCode(), language.getName());
	}

}
