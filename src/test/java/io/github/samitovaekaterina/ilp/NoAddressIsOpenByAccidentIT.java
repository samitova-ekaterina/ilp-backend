package io.github.samitovaekaterina.ilp;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.request;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.function.ToIntFunction;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationContext;
import org.springframework.http.HttpMethod;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.servlet.mvc.method.RequestMappingInfo;
import org.springframework.web.servlet.mvc.method.RequestMappingInfoHandlerMapping;

class NoAddressIsOpenByAccidentIT extends IntegrationTestBase {

    private static final int NOT_SIGNED_IN = 401;

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ApplicationContext context;

    @Test
    void everyAddressOutsideTheOpenListRequiresSignIn() {
        List<Address> addresses = everyAddressOfTheApplication();

        // The list must really be the list of the application, or the check below would check nothing.
        assertThat(addresses)
                .contains(
                        new Address(HttpMethod.GET, "/api/v1/languages"),
                        new Address(HttpMethod.GET, "/actuator/info"));
        assertThat(openByAccident(addresses, this::statusWithoutSignIn)).isEmpty();
    }

    @Test
    void theCheckNamesAnAddressThatAnswersWithoutSignIn() {
        Address forgotten = new Address(HttpMethod.GET, "/api/v1/forgotten");
        Address closed = new Address(HttpMethod.GET, "/api/v1/closed");

        List<Address> found =
                openByAccident(List.of(forgotten, closed), address -> address.equals(forgotten) ? 200 : NOT_SIGNED_IN);

        assertThat(found).containsExactly(forgotten);
    }

    @Test
    void theCheckNamesAnOpenAddressUsedWithAnotherMethod() {
        Address changingLanguages = new Address(HttpMethod.POST, "/api/v1/languages");

        assertThat(openByAccident(List.of(changingLanguages), address -> 200)).containsExactly(changingLanguages);
    }

    @Test
    void theCheckAcceptsTheAddressesMeantToBeOpen() {
        List<Address> meantToBeOpen = List.of(
                new Address(HttpMethod.GET, "/api/v1/languages"),
                new Address(HttpMethod.GET, "/actuator/health"),
                new Address(HttpMethod.GET, "/actuator/health/x"),
                new Address(HttpMethod.GET, "/actuator/info"),
                new Address(HttpMethod.GET, "/v3/api-docs"),
                new Address(HttpMethod.GET, "/v3/api-docs/x"),
                new Address(HttpMethod.GET, "/swagger-ui.html"),
                new Address(HttpMethod.GET, "/swagger-ui/x"));

        assertThat(openByAccident(meantToBeOpen, address -> 200)).isEmpty();
    }

    // Written here a second time on purpose, apart from the security settings: opening an address takes two edits.
    private static boolean meantToBeOpen(Address address) {
        String path = address.path();
        return address.method().equals(HttpMethod.GET)
                && (path.equals("/api/v1/languages")
                        || path.equals("/actuator/health")
                        || path.startsWith("/actuator/health/")
                        || path.equals("/actuator/info")
                        || path.equals("/v3/api-docs")
                        || path.startsWith("/v3/api-docs/")
                        || path.equals("/swagger-ui.html")
                        || path.startsWith("/swagger-ui/"));
    }

    private static List<Address> openByAccident(List<Address> addresses, ToIntFunction<Address> statusWithoutSignIn) {
        return addresses.stream()
                .filter(address -> !meantToBeOpen(address))
                .filter(address -> statusWithoutSignIn.applyAsInt(address) != NOT_SIGNED_IN)
                .toList();
    }

    private int statusWithoutSignIn(Address address) {
        try {
            // The anti-forgery token is sent, so that a refusal can only mean "not signed in".
            return mockMvc.perform(request(address.method(), address.path()).with(AntiForgery.token()))
                    .andReturn()
                    .getResponse()
                    .getStatus();
        } catch (Exception e) {
            throw new IllegalStateException("The request to " + address + " failed", e);
        }
    }

    // Controllers of the application, service addresses and the API description: everything Spring MVC has mapped.
    private List<Address> everyAddressOfTheApplication() {
        List<Address> addresses = new ArrayList<>();
        for (RequestMappingInfoHandlerMapping mapping :
                context.getBeansOfType(RequestMappingInfoHandlerMapping.class).values()) {
            for (RequestMappingInfo info : mapping.getHandlerMethods().keySet()) {
                Set<RequestMethod> methods = info.getMethodsCondition().getMethods();
                for (String pattern : info.getPatternValues()) {
                    String path = pattern.replaceAll("\\{[^}]*}", "x")
                            .replace("**", "x")
                            .replace("*", "x");
                    if (methods.isEmpty()) {
                        addresses.add(new Address(HttpMethod.GET, path));
                    }
                    for (RequestMethod method : methods) {
                        addresses.add(new Address(method.asHttpMethod(), path));
                    }
                }
            }
        }
        return addresses;
    }

    private record Address(HttpMethod method, String path) {}
}
