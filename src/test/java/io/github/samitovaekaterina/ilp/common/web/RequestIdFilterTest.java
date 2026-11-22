package io.github.samitovaekaterina.ilp.common.web;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.jayway.jsonpath.JsonPath;
import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@ExtendWith(OutputCaptureExtension.class)
class RequestIdFilterTest {

    private final MockMvc mockMvc = MockMvcBuilders.standaloneSetup(new ProbeController())
            .setControllerAdvice(new GlobalExceptionHandler())
            .addFilters(new RequestIdFilter())
            .build();

    @Test
    void handlerSeesTheNumberThatIsSentToTheClient() throws Exception {
        MockHttpServletResponse response = mockMvc.perform(get("/probe/request-id"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse();
        String sent = response.getHeader(RequestIdFilter.HEADER);
        assertThat(sent).isNotBlank();
        assertThat(response.getContentAsString()).isEqualTo(sent);
    }

    @Test
    void errorBodyCarriesTheNumberFromTheHeader() throws Exception {
        MockHttpServletResponse response = mockMvc.perform(get("/probe/items/not-a-number"))
                .andExpect(status().isBadRequest())
                .andReturn()
                .getResponse();
        String inBody = JsonPath.read(response.getContentAsString(), "$.requestId");
        assertThat(inBody).isEqualTo(response.getHeader(RequestIdFilter.HEADER));
    }

    @Test
    void numberIsRemovedWhenTheRequestEnds() throws Exception {
        mockMvc.perform(get("/probe/request-id")).andExpect(status().isOk());
        assertThat(MDC.get(RequestIdFilter.MDC_KEY)).isNull();
    }

    @Test
    void logShowsTheRouteTemplateNotTheRawPath(CapturedOutput output) throws Exception {
        mockMvc.perform(get("/probe/items/42")).andExpect(status().isOk());
        assertThat(output).contains("GET /probe/items/{id} -> 200").doesNotContain("/probe/items/42");
    }

    @Test
    void logShowsTheMeasuredTimeOfTheRequestInMilliseconds() throws Exception {
        Logger filterLog = (Logger) LoggerFactory.getLogger(RequestIdFilter.class);
        ListAppender<ILoggingEvent> logRecords = new ListAppender<>();
        logRecords.start();
        filterLog.addAppender(logRecords);
        try {
            mockMvc.perform(get("/probe/items/42")).andExpect(status().isOk());
        } finally {
            filterLog.detachAppender(logRecords);
        }

        ILoggingEvent requestLine = logRecords.list.getLast();
        long nanoseconds = requestLine.getKeyValuePairs().stream()
                .filter(pair -> pair.key.equals("event.duration"))
                .map(pair -> (Long) pair.value)
                .findFirst()
                .orElseThrow();
        // A request of a test never takes a minute: a wrong sign in the calculation gives a far larger number.
        assertThat(nanoseconds).isPositive().isLessThan(Duration.ofMinutes(1).toNanos());
        assertThat(requestLine.getFormattedMessage()).endsWith(" in " + nanoseconds / 1_000_000 + " ms");
    }

    // Exists only in this test: it returns what a handler sees while the request is being processed.
    @RestController
    static class ProbeController {

        @GetMapping("/probe/request-id")
        String requestId() {
            return MDC.get(RequestIdFilter.MDC_KEY);
        }

        @GetMapping("/probe/items/{id}")
        String item(@PathVariable("id") long id) {
            return "item " + id;
        }
    }
}
