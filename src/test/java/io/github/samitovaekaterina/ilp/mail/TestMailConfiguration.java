package io.github.samitovaekaterina.ilp.mail;

import io.github.samitovaekaterina.ilp.mail.service.RecordingMailService;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;

@TestConfiguration
public class TestMailConfiguration {

    // Takes the place of the real service even when a developer has the key of the mail service set.
    @Bean
    @Primary
    RecordingMailService recordingMailService() {
        return new RecordingMailService();
    }
}
