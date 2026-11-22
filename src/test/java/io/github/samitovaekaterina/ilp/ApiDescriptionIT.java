package io.github.samitovaekaterina.ilp;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.MockMvc;

class ApiDescriptionIT extends IntegrationTestBase {

    private static final Path SAVED = Path.of("docs", "api", "openapi.json");
    private static final Path CURRENT = Path.of("build", "api", "openapi.json");

    private static final ObjectMapper JSON = new ObjectMapper()
            .enable(SerializationFeature.ORDER_MAP_ENTRIES_BY_KEYS)
            .enable(SerializationFeature.INDENT_OUTPUT);

    @Autowired
    private MockMvc mockMvc;

    @Test
    void theApiDescriptionMatchesTheSavedCopy() throws Exception {
        String current = currentDescription();
        // Written on every run: after an intended change of the API this file is copied over the saved one.
        Files.createDirectories(CURRENT.getParent());
        Files.writeString(CURRENT, current, StandardCharsets.UTF_8);

        String saved = Files.readString(SAVED, StandardCharsets.UTF_8).replace("\r\n", "\n");

        assertThat(current)
                .as("The API differs from %s. If the change is intended, copy %s over it", SAVED, CURRENT)
                .isEqualTo(saved);
    }

    private String currentDescription() throws Exception {
        String body = mockMvc.perform(get("/v3/api-docs"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString(StandardCharsets.UTF_8);
        ObjectNode description = (ObjectNode) JSON.readTree(body);
        // The address of the server differs from one environment to another and is not a part of the contract.
        description.remove("servers");
        // Plain maps are written with sorted keys, so the saved file does not change with the order of fields.
        Object sorted = JSON.treeToValue(description, Object.class);
        return JSON.writeValueAsString(sorted).replace("\r\n", "\n") + "\n";
    }
}
