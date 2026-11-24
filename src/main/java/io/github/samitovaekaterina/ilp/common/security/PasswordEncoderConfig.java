package io.github.samitovaekaterina.ilp.common.security;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.crypto.argon2.Argon2PasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

@Configuration
@EnableConfigurationProperties(PasswordHashSettings.class)
public class PasswordEncoderConfig {

    // Argon2id itself, without the wrapper that puts "{argon2}" in front: the hashes in the database have no such mark.
    @Bean
    PasswordEncoder passwordEncoder(PasswordHashSettings settings) {
        return new Argon2PasswordEncoder(
                settings.saltLengthBytes(),
                settings.hashLengthBytes(),
                settings.parallelism(),
                settings.memoryKib(),
                settings.iterations());
    }
}
