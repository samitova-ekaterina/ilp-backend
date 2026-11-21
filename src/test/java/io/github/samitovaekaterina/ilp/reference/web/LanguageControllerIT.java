package io.github.samitovaekaterina.ilp.reference.web;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import io.github.samitovaekaterina.ilp.IntegrationTestBase;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.MockMvc;

class LanguageControllerIT extends IntegrationTestBase {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void languagesComeFromTheDatabaseSortedByName() throws Exception {
        mockMvc.perform(get("/api/v1/languages"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].code").value("en"))
                .andExpect(jsonPath("$[0].name").value("English"))
                .andExpect(jsonPath("$[1].code").value("ru"))
                .andExpect(jsonPath("$[1].name").value("Russian"));
    }
}
