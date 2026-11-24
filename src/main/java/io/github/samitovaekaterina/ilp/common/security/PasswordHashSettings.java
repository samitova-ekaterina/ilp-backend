package io.github.samitovaekaterina.ilp.common.security;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("ilp.security.password-hash")
public record PasswordHashSettings(
        int memoryKib, int iterations, int parallelism, int saltLengthBytes, int hashLengthBytes) {}
