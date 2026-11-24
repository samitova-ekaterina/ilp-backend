package io.github.samitovaekaterina.ilp.mail.brevo;

import io.github.samitovaekaterina.ilp.mail.service.Mail;
import io.github.samitovaekaterina.ilp.mail.service.MailService;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/** Sends letters through the HTTP API of Brevo. */
@Service
public class BrevoMailService implements MailService {

    static final String PATH = "/smtp/email";

    static final String KEY_HEADER = "api-key";

    private static final Logger log = LoggerFactory.getLogger(BrevoMailService.class);

    private final RestClient client;

    private final MailSettings settings;

    public BrevoMailService(@Qualifier(BrevoConfig.CLIENT) RestClient client, MailSettings settings) {
        this.client = client;
        this.settings = settings;
    }

    @Override
    public boolean send(Mail mail) {
        String key = settings.brevo().apiKey();
        if (!StringUtils.hasText(key)) {
            log.warn("A letter was not sent: the key of the mail service is not set");
            return false;
        }
        Sender sender = new Sender(settings.senderName(), settings.senderAddress());
        Message message = new Message(sender, List.of(new Recipient(mail.to())), mail.subject(), mail.text());
        try {
            client.post()
                    .uri(PATH)
                    .header(KEY_HEADER, key)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(message)
                    .retrieve()
                    .toBodilessEntity();
            return true;
        } catch (RestClientException e) {
            // Only the kind of the failure is logged: its text may hold the address of the recipient.
            log.warn("A letter was not sent: {}", e.getClass().getSimpleName());
            return false;
        }
    }

    record Message(Sender sender, List<Recipient> to, String subject, String textContent) {}

    record Sender(String name, String email) {}

    record Recipient(String email) {}
}
