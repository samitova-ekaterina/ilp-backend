package io.github.samitovaekaterina.ilp;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

class ServiceEndpointsIT extends IntegrationTestBase {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void healthIsOpenAndShowsNoDetails() throws Exception {
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"))
                .andExpect(jsonPath("$.components").doesNotExist());
    }

    @Test
    void infoShowsTheBuildVersion() throws Exception {
        mockMvc.perform(get("/actuator/info"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.build.version").exists());
    }

    @Test
    void thePageOfTheApiDescriptionIsOpen() throws Exception {
        int status = mockMvc.perform(get("/swagger-ui.html"))
                .andReturn()
                .getResponse()
                .getStatus();

        // The address forwards the browser to the page itself, so the answer is not 200, but it is not a refusal.
        assertThat(status).isNotIn(401, 403, 404);
    }

    @Test
    void theHealthAnswerDoesNotTellWhetherTheVisitorIsSignedIn() throws Exception {
        mockMvc.perform(get("/actuator/health").with(user("1")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.components").doesNotExist());
    }

    @Test
    void metricsRefuseAVisitorWithoutTheLocalProfile() throws Exception {
        mockMvc.perform(get("/actuator/metrics")).andExpect(status().isUnauthorized());
    }

    @Test
    void metricsDoNotExistEvenForASignedInUserWithoutTheLocalProfile() throws Exception {
        mockMvc.perform(get("/actuator/metrics").with(user("1"))).andExpect(status().isNotFound());
    }

    @Test
    void otherServiceAddressesRefuseAVisitor() throws Exception {
        mockMvc.perform(get("/actuator/env")).andExpect(status().isUnauthorized());
    }

    @Test
    void otherServiceAddressesDoNotExistEvenForASignedInUser() throws Exception {
        mockMvc.perform(get("/actuator/env").with(user("1"))).andExpect(status().isNotFound());
    }

    @Test
    void theListOfServiceAddressesDoesNotExistEvenForASignedInUser() throws Exception {
        mockMvc.perform(get("/actuator").with(user("1"))).andExpect(status().isNotFound());
    }

    @Nested
    @ActiveProfiles("local")
    class WithTheLocalProfile {

        @Test
        void metricsAreOpen() throws Exception {
            mockMvc.perform(get("/actuator/metrics")).andExpect(status().isOk());
        }
    }
}
