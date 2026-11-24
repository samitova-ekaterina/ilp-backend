package io.github.samitovaekaterina.ilp.mail.brevo;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("ilp.mail")
public record MailSettings(String senderAddress, String senderName, Brevo brevo) {

    public record Brevo(String apiKey, String baseUrl, Duration connectTimeout, Duration readTimeout) {}
}
