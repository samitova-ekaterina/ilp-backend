package io.github.samitovaekaterina.ilp;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.test.web.servlet.MockMvc;

@ExtendWith(OutputCaptureExtension.class)
class RequestLogIT extends IntegrationTestBase {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void unknownAddressIsNotWrittenToTheLog(CapturedOutput output) throws Exception {
        mockMvc.perform(get("/api/v1/users/anna@example.com").with(user("1"))).andExpect(status().isNotFound());
        assertThat(output).contains("GET unmatched -> 404").doesNotContain("anna@example.com");
    }

    @Test
    void theAddressOfARefusedRequestIsNotWrittenToTheLog(CapturedOutput output) throws Exception {
        mockMvc.perform(get("/api/v1/users/boris@example.com")).andExpect(status().isUnauthorized());
        assertThat(output).contains("GET unmatched -> 401").doesNotContain("boris@example.com");
    }
}
