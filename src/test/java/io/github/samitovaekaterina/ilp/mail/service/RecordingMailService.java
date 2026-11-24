package io.github.samitovaekaterina.ilp.mail.service;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

/** Stands in for the mail service in tests: keeps the letters in memory instead of sending them. */
public class RecordingMailService implements MailService {

    private final List<Mail> letters = new CopyOnWriteArrayList<>();

    @Override
    public boolean send(Mail mail) {
        letters.add(mail);
        return true;
    }

    public List<Mail> letters() {
        return List.copyOf(letters);
    }

    public void forgetLetters() {
        letters.clear();
    }
}
