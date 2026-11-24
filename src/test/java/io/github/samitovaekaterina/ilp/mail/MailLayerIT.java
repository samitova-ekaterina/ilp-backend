package io.github.samitovaekaterina.ilp.mail;

import static org.assertj.core.api.Assertions.assertThat;

import io.github.samitovaekaterina.ilp.IntegrationTestBase;
import io.github.samitovaekaterina.ilp.mail.service.Mail;
import io.github.samitovaekaterina.ilp.mail.service.MailService;
import io.github.samitovaekaterina.ilp.mail.service.RecordingMailService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

class MailLayerIT extends IntegrationTestBase {

    @Autowired
    private MailService mailService;

    @Autowired
    private RecordingMailService sentLetters;

    @AfterEach
    void forgetTheLetters() {
        sentLetters.forgetLetters();
    }

    @Test
    void aLetterSentInATestStaysInMemoryAndCanBeRead() {
        Mail letter = new Mail("anna@example.com", "Confirm your address", "Open the link to confirm your address.");

        boolean sent = mailService.send(letter);

        assertThat(sent).isTrue();
        assertThat(sentLetters.letters()).containsExactly(letter);
    }

    @Test
    void theApplicationCodeGetsTheStandInNotTheRealService() {
        assertThat(mailService).isSameAs(sentLetters);
    }
}
