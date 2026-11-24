package io.github.samitovaekaterina.ilp.mail.brevo;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.jsonPath;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withException;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import io.github.samitovaekaterina.ilp.mail.service.Mail;
import java.io.IOException;
import java.time.Duration;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class BrevoMailServiceTest {

    private static final String ADDRESS = "https://mail.example/v3";

    private static final Mail LETTER =
            new Mail("anna@example.com", "Confirm your address", "Open the link to confirm your address.");

    private final RestClient.Builder builder = RestClient.builder().baseUrl(ADDRESS);

    // Stands in for Brevo inside the HTTP client: no request leaves the test.
    private final MockRestServiceServer brevo =
            MockRestServiceServer.bindTo(builder).build();

    private final Logger serviceLog = (Logger) LoggerFactory.getLogger(BrevoMailService.class);

    private final ListAppender<ILoggingEvent> logRecords = new ListAppender<>();

    @BeforeEach
    void collectTheLogOfTheService() {
        logRecords.start();
        serviceLog.addAppender(logRecords);
    }

    @AfterEach
    void stopCollectingTheLog() {
        serviceLog.detachAppender(logRecords);
    }

    @Test
    void theLetterGoesToBrevoWithTheKeyInTheHeader() {
        brevo.expect(requestTo(ADDRESS + "/smtp/email"))
                .andExpect(method(HttpMethod.POST))
                .andExpect(header("api-key", "test-key"))
                .andExpect(jsonPath("$.sender.name").value("ILP"))
                .andExpect(jsonPath("$.sender.email").value("no-reply@example.com"))
                .andExpect(jsonPath("$.to.length()").value(1))
                .andExpect(jsonPath("$.to[0].email").value("anna@example.com"))
                .andExpect(jsonPath("$.subject").value("Confirm your address"))
                .andExpect(jsonPath("$.textContent").value("Open the link to confirm your address."))
                .andRespond(withStatus(HttpStatus.CREATED)
                        .contentType(MediaType.APPLICATION_JSON)
                        .body("{\"messageId\":\"<1@relay.example>\"}"));

        boolean sent = serviceWithKey("test-key").send(LETTER);

        assertThat(sent).isTrue();
        assertThat(logged()).isEmpty();
        brevo.verify();
    }

    @Test
    void aRefusalOfBrevoIsLoggedWithoutTheAddressAndDoesNotThrow() {
        brevo.expect(requestTo(ADDRESS + "/smtp/email"))
                .andRespond(withStatus(HttpStatus.BAD_REQUEST)
                        .contentType(MediaType.APPLICATION_JSON)
                        .body("{\"code\":\"invalid_parameter\",\"message\":\"anna@example.com is not valid\"}"));

        boolean sent = serviceWithKey("test-key").send(LETTER);

        assertThat(sent).isFalse();
        assertThat(logged())
                .hasSize(1)
                .allSatisfy(line ->
                        assertThat(line).startsWith("A letter was not sent").doesNotContain("anna@example.com"));
    }

    @Test
    void aFailureOfBrevoIsReportedAndDoesNotThrow() {
        brevo.expect(requestTo(ADDRESS + "/smtp/email")).andRespond(withServerError());

        boolean sent = serviceWithKey("test-key").send(LETTER);

        assertThat(sent).isFalse();
        assertThat(logged()).hasSize(1);
    }

    @Test
    void anUnreachableBrevoIsReportedAndDoesNotThrow() {
        brevo.expect(requestTo(ADDRESS + "/smtp/email")).andRespond(withException(new IOException("no answer")));

        boolean sent = serviceWithKey("test-key").send(LETTER);

        assertThat(sent).isFalse();
        assertThat(logged()).hasSize(1);
    }

    @Test
    void withoutTheKeyNoRequestIsMade() {
        boolean sent = serviceWithKey("").send(LETTER);

        assertThat(sent).isFalse();
        assertThat(logged()).containsExactly("A letter was not sent: the key of the mail service is not set");
        // No request was expected, so any request would have failed the test.
        brevo.verify();
    }

    private List<String> logged() {
        return logRecords.list.stream().map(ILoggingEvent::getFormattedMessage).toList();
    }

    private BrevoMailService serviceWithKey(String key) {
        MailSettings.Brevo settings =
                new MailSettings.Brevo(key, ADDRESS, Duration.ofSeconds(2), Duration.ofSeconds(5));
        return new BrevoMailService(builder.build(), new MailSettings("no-reply@example.com", "ILP", settings));
    }
}
