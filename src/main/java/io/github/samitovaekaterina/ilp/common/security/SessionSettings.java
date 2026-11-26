package io.github.samitovaekaterina.ilp.common.security;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("ilp.security")
public record SessionSettings(Duration sessionLifetime) {}
