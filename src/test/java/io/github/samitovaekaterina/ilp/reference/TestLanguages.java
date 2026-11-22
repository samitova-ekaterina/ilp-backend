package io.github.samitovaekaterina.ilp.reference;

import io.github.samitovaekaterina.ilp.reference.model.Language;
import org.springframework.test.util.ReflectionTestUtils;

public final class TestLanguages {

    private TestLanguages() {}

    // The class of the table has no setters on purpose, so a fast test fills its fields directly.
    public static Language language(String code, String name) {
        Language language = new Language() {};
        ReflectionTestUtils.setField(language, "code", code);
        ReflectionTestUtils.setField(language, "name", name);
        return language;
    }
}
