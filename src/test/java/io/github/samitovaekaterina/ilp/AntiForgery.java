package io.github.samitovaekaterina.ilp;

import jakarta.servlet.http.Cookie;
import java.util.ArrayList;
import java.util.List;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

/** Sends the anti-forgery token the way the front end does: the value of the cookie repeated in the header. */
public final class AntiForgery {

    public static final String COOKIE = "XSRF-TOKEN";

    public static final String HEADER = "X-XSRF-TOKEN";

    private static final String VALUE = "the-token-of-this-test";

    private AntiForgery() {}

    // Not the ready helper of Spring Security: it replaces the token store of the application for all later tests.
    public static RequestPostProcessor token() {
        return request -> {
            Cookie[] sent = request.getCookies();
            List<Cookie> cookies = new ArrayList<>(sent == null ? List.of() : List.of(sent));
            cookies.add(new Cookie(COOKIE, VALUE));
            request.setCookies(cookies.toArray(Cookie[]::new));
            request.addHeader(HEADER, VALUE);
            return request;
        };
    }
}
