package io.github.samitovaekaterina.ilp.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.HttpMethod;

class OpenAddressesTest {

    @ParameterizedTest
    @ValueSource(
            strings = {
                "/actuator/health",
                "/actuator/health/liveness",
                "/actuator/info",
                "/v3/api-docs",
                "/v3/api-docs/swagger-config",
                "/swagger-ui.html",
                "/swagger-ui/index.html",
                "/api/v1/languages"
            })
    void theListedAddressesAreOpenForReading(String path) {
        assertThat(OpenAddresses.isOpen(HttpMethod.GET, path)).isTrue();
    }

    @ParameterizedTest
    @ValueSource(
            strings = {
                "/",
                "/actuator",
                "/actuator/env",
                "/actuator/metrics",
                "/actuator/healthy",
                "/api/v1/languages/1",
                "/api/v1/users/me"
            })
    void anyOtherAddressIsClosed(String path) {
        assertThat(OpenAddresses.isOpen(HttpMethod.GET, path)).isFalse();
    }

    @Test
    void anOpenAddressIsOpenOnlyForReading() {
        assertThat(OpenAddresses.isOpen(HttpMethod.POST, "/api/v1/languages")).isFalse();
        assertThat(OpenAddresses.isOpen(HttpMethod.DELETE, "/actuator/health")).isFalse();
    }

    @Test
    void metricsAreOpenOnlyOnADeveloperComputer() {
        assertThat(OpenAddresses.on(false))
                .extracting(OpenAddresses.Address::pattern)
                .doesNotContain("/actuator/metrics");
        assertThat(OpenAddresses.on(true))
                .extracting(OpenAddresses.Address::pattern)
                .contains("/actuator/metrics", "/actuator/metrics/**")
                .containsAll(OpenAddresses.on(false).stream()
                        .map(OpenAddresses.Address::pattern)
                        .toList());
    }
}
