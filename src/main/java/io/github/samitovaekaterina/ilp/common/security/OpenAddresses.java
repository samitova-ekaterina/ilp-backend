package io.github.samitovaekaterina.ilp.common.security;

import java.util.List;
import java.util.stream.Stream;
import org.springframework.http.HttpMethod;
import org.springframework.http.server.PathContainer;
import org.springframework.web.util.pattern.PathPatternParser;

/** The only list of what answers without sign-in; every other address is closed. */
public final class OpenAddresses {

    public static final String DEVELOPER_PROFILE = "local";

    private static final List<Address> ALWAYS = List.of(
            new Address(HttpMethod.GET, "/actuator/health"),
            new Address(HttpMethod.GET, "/actuator/health/**"),
            new Address(HttpMethod.GET, "/actuator/info"),
            new Address(HttpMethod.GET, "/v3/api-docs"),
            new Address(HttpMethod.GET, "/v3/api-docs/**"),
            new Address(HttpMethod.GET, "/swagger-ui.html"),
            new Address(HttpMethod.GET, "/swagger-ui/**"),
            new Address(HttpMethod.GET, "/api/v1/languages"));

    private static final List<Address> ONLY_ON_A_DEVELOPER_COMPUTER = List.of(
            new Address(HttpMethod.GET, "/actuator/metrics"), new Address(HttpMethod.GET, "/actuator/metrics/**"));

    private OpenAddresses() {}

    public static List<Address> on(boolean developerComputer) {
        return developerComputer
                ? Stream.concat(ALWAYS.stream(), ONLY_ON_A_DEVELOPER_COMPUTER.stream())
                        .toList()
                : ALWAYS;
    }

    /** Tells whether the address is open on the hosting platform. */
    public static boolean isOpen(HttpMethod method, String path) {
        PathContainer container = PathContainer.parsePath(path);
        return ALWAYS.stream()
                .anyMatch(address -> address.method().equals(method)
                        && PathPatternParser.defaultInstance
                                .parse(address.pattern())
                                .matches(container));
    }

    public record Address(HttpMethod method, String pattern) {}
}
