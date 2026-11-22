package io.github.samitovaekaterina.ilp.reference.web;

import static io.github.samitovaekaterina.ilp.reference.TestLanguages.language;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import io.github.samitovaekaterina.ilp.reference.service.LanguageService;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class LanguageControllerTest {

    @Test
    void everyLanguageIsReturnedWithItsCodeAndNameOnly() throws Exception {
        LanguageService service = () -> List.of(language("en", "English"), language("ru", "Russian"));
        MockMvc mockMvc =
                MockMvcBuilders.standaloneSetup(new LanguageController(service)).build();

        mockMvc.perform(get("/api/v1/languages"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].code").value("en"))
                .andExpect(jsonPath("$[0].name").value("English"))
                .andExpect(jsonPath("$[1].code").value("ru"))
                .andExpect(jsonPath("$[1].name").value("Russian"))
                .andExpect(jsonPath("$[0].length()").value(2));
    }
}
