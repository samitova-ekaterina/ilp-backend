package io.github.samitovaekaterina.ilp.reference.service;

import static io.github.samitovaekaterina.ilp.reference.TestLanguages.language;
import static org.assertj.core.api.Assertions.assertThat;

import io.github.samitovaekaterina.ilp.reference.model.Language;
import java.util.List;
import org.junit.jupiter.api.Test;

class LanguageServiceImplTest {

    @Test
    void languagesAreReturnedInTheOrderOfTheRepository() {
        Language english = language("en", "English");
        Language russian = language("ru", "Russian");
        LanguageService service = new LanguageServiceImpl(() -> List.of(english, russian));

        List<Language> languages = service.findAll();

        assertThat(languages).containsExactly(english, russian);
    }
}
