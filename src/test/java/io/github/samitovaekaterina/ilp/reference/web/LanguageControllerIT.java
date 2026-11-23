package io.github.samitovaekaterina.ilp.reference.web;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import io.github.samitovaekaterina.ilp.IntegrationTestBase;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.MockMvc;

class LanguageControllerIT extends IntegrationTestBase {

    @Autowired
    private MockMvc mockMvc;

    @AfterEach
    void removeTheAddedLanguage() {
        asOwner().update("DELETE FROM core.language WHERE code = 'be'");
    }

    @Test
    void languagesComeFromTheDatabaseSortedByName() throws Exception {
        // Added last but first by the alphabet: without the sorting it would stand at the end of the list.
        asOwner().update("INSERT INTO core.language (code, name) VALUES ('be', 'Belarusian')");

        mockMvc.perform(get("/api/v1/languages"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(3))
                .andExpect(jsonPath("$[0].code").value("be"))
                .andExpect(jsonPath("$[0].name").value("Belarusian"))
                .andExpect(jsonPath("$[1].code").value("en"))
                .andExpect(jsonPath("$[1].name").value("English"))
                .andExpect(jsonPath("$[2].code").value("ru"))
                .andExpect(jsonPath("$[2].name").value("Russian"));
    }
}
