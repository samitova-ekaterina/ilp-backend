package io.github.samitovaekaterina.ilp.mail.service;

public interface MailService {

    /** Returns false when the letter was not handed over to the mail service; a failure never throws. */
    boolean send(Mail mail);
}
