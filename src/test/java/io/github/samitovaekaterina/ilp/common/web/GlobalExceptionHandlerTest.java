package io.github.samitovaekaterina.ilp.common.web;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@ExtendWith(OutputCaptureExtension.class)
class GlobalExceptionHandlerTest {

    private final MockMvc mockMvc = MockMvcBuilders.standaloneSetup(new ProbeController())
            .setControllerAdvice(new GlobalExceptionHandler())
            .build();

    @Test
    void invalidInputReturns400InTheCommonFormat() throws Exception {
        mockMvc.perform(get("/probe/items/not-a-number"))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.status").value(400))
                .andExpect(jsonPath("$.code").value("common.bad-request"));
    }

    @Test
    void unexpectedFailureReturns500WithoutInternalDetails() throws Exception {
        mockMvc.perform(get("/probe/failure"))
                .andExpect(status().isInternalServerError())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.code").value("common.internal-error"))
                .andExpect(jsonPath("$.detail").value(ErrorCode.INTERNAL_ERROR.getDetail()))
                .andExpect(content().string(not(containsString("secret reason"))));
    }

    @Test
    void unexpectedFailureIsWrittenToTheLog(CapturedOutput output) throws Exception {
        mockMvc.perform(get("/probe/failure")).andExpect(status().isInternalServerError());

        assertThat(output).contains("Server error");
    }

    @Test
    void mistakeOfTheClientIsNotWrittenToTheLogAsAServerError(CapturedOutput output) throws Exception {
        mockMvc.perform(get("/probe/items/not-a-number")).andExpect(status().isBadRequest());

        assertThat(output).doesNotContain("Server error");
    }

    @Test
    void invalidFormReturns400WithTheFieldsToCorrect() throws Exception {
        mockMvc.perform(post("/probe/forms")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"\",\"email\":\"not-an-email\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("common.bad-request"))
                .andExpect(jsonPath("$.errors[?(@.field == 'name')].code").value("not-blank"))
                .andExpect(jsonPath("$.errors[?(@.field == 'email')].code").value("email"))
                .andExpect(content().string(not(containsString("not-an-email"))));
    }

    @Test
    void pageBelowTheMinimumReturns400NamingTheParameter() throws Exception {
        mockMvc.perform(get("/probe/pages").param("page", "-1"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors[0].field").value("page"))
                .andExpect(jsonPath("$.errors[0].code").value("min"));
    }

    @Test
    void pageOfTheWrongTypeReturns400NamingTheParameter() throws Exception {
        mockMvc.perform(get("/probe/pages").param("page", "oops"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors[0].field").value("page"))
                .andExpect(jsonPath("$.errors[0].code").value("type-mismatch"))
                .andExpect(content().string(not(containsString("oops"))));
    }

    @Test
    void missingPageReturns400NamingTheParameter() throws Exception {
        mockMvc.perform(get("/probe/pages"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors[0].field").value("page"))
                .andExpect(jsonPath("$.errors[0].code").value("missing"));
    }

    @Test
    void pathVariableBelowTheMinimumReturns400NamingTheVariable() throws Exception {
        mockMvc.perform(get("/probe/items/0"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors[0].field").value("id"))
                .andExpect(jsonPath("$.errors[0].code").value("min"));
    }

    @Test
    void parameterWithoutAnExplicitNameIsNamedAsInTheAddress() throws Exception {
        mockMvc.perform(get("/probe/sizes").param("size", "0"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors[0].field").value("size"))
                .andExpect(jsonPath("$.errors[0].code").value("min"));
    }

    @Test
    void invalidFormNextToACheckedParameterReturns400WithTheFieldToCorrect() throws Exception {
        mockMvc.perform(post("/probe/forms-on-a-page")
                        .param("page", "0")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"\",\"email\":\"reader@example.com\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors.length()").value(1))
                .andExpect(jsonPath("$.errors[0].field").value("name"))
                .andExpect(jsonPath("$.errors[0].code").value("not-blank"));
    }

    @Test
    void invalidResultOfTheServerReturns500WithoutFieldsToCorrect() throws Exception {
        mockMvc.perform(get("/probe/broken-result"))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.code").value("common.internal-error"))
                .andExpect(jsonPath("$.errors").doesNotExist());
    }

    // Exists only in this test: the application has no request yet that can fail on demand.
    @RestController
    static class ProbeController {

        @GetMapping("/probe/items/{id}")
        String item(@PathVariable("id") @Min(1) long itemId) {
            return "item " + itemId;
        }

        @GetMapping("/probe/failure")
        String failure() {
            throw new IllegalStateException("secret reason");
        }

        @PostMapping("/probe/forms")
        String form(@Valid @RequestBody ProbeForm form) {
            return "accepted";
        }

        @GetMapping("/probe/pages")
        String page(@RequestParam("page") @Min(0) int pageIndex) {
            return "page " + pageIndex;
        }

        @GetMapping("/probe/sizes")
        String size(@RequestParam @Min(1) int size) {
            return "size " + size;
        }

        @PostMapping("/probe/forms-on-a-page")
        String formOnAPage(@RequestParam("page") @Min(0) int pageIndex, @Valid @RequestBody ProbeForm form) {
            return "accepted";
        }

        @GetMapping("/probe/broken-result")
        @Min(0)
        int brokenResult() {
            return -1;
        }
    }

    record ProbeForm(@NotBlank String name, @Email String email) {}
}
