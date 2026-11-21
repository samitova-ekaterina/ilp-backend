package io.github.samitovaekaterina.ilp;

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
    void metricsAreClosedWithoutTheLocalProfile() throws Exception {
        mockMvc.perform(get("/actuator/metrics")).andExpect(status().isNotFound());
    }

    @Test
    void otherServiceAddressesAreClosed() throws Exception {
        mockMvc.perform(get("/actuator/env")).andExpect(status().isNotFound());
    }

    @Test
    void theListOfServiceAddressesIsClosed() throws Exception {
        mockMvc.perform(get("/actuator")).andExpect(status().isNotFound());
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
