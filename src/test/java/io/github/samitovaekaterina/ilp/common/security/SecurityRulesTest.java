package io.github.samitovaekaterina.ilp.common.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import io.github.samitovaekaterina.ilp.AntiForgery;
import jakarta.servlet.http.Cookie;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

// The security rules with a controller of this test only: no database and no other part of the application.
@WebMvcTest(controllers = SecurityRulesTest.ProbeController.class)
@Import({SecurityConfig.class, RefusalHandler.class, SecurityRulesTest.ProbeController.class})
class SecurityRulesTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void aClosedAddressRefusesAVisitorWhoIsNotSignedInInTheCommonErrorFormat() throws Exception {
        mockMvc.perform(get("/probe/closed"))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.status").value(401))
                .andExpect(jsonPath("$.code").value("auth.unauthenticated"))
                .andExpect(jsonPath("$.requestId").isNotEmpty())
                .andExpect(header().exists("X-Request-Id"));
    }

    @Test
    void anAddressThatDoesNotExistAnswersAVisitorTheSameAsAClosedOne() throws Exception {
        mockMvc.perform(get("/probe/nothing"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("auth.unauthenticated"));
    }

    @Test
    void aRefusalDoesNotCreateASession() throws Exception {
        MvcResult refusal = mockMvc.perform(get("/probe/closed"))
                .andExpect(status().isUnauthorized())
                .andReturn();

        assertThat(refusal.getRequest().getSession(false)).isNull();
    }

    @Test
    void aSignedInUserReadsAClosedAddressWithoutTheToken() throws Exception {
        mockMvc.perform(get("/probe/closed").with(user("1"))).andExpect(status().isOk());
    }

    @Test
    void anOpenAddressAnswersWithoutSignIn() throws Exception {
        mockMvc.perform(get("/api/v1/languages")).andExpect(status().isOk());
    }

    @Test
    void anOpenAddressIsOpenOnlyForReading() throws Exception {
        mockMvc.perform(post("/api/v1/languages").with(AntiForgery.token()))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("auth.unauthenticated"));
    }

    @Test
    void aChangingRequestWithoutTheTokenIsRefusedInTheCommonErrorFormat() throws Exception {
        mockMvc.perform(post("/probe/closed").with(user("1")))
                .andExpect(status().isForbidden())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.status").value(403))
                .andExpect(jsonPath("$.code").value("auth.csrf"))
                .andExpect(jsonPath("$.requestId").isNotEmpty());
    }

    @Test
    void aChangingRequestWithAWrongTokenIsRefused() throws Exception {
        mockMvc.perform(post("/probe/closed")
                        .with(user("1"))
                        .cookie(new Cookie(AntiForgery.COOKIE, "the-token-of-the-user"))
                        .header(AntiForgery.HEADER, "a-guess-of-another-site"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("auth.csrf"));
    }

    @Test
    void aChangingRequestThatReturnsTheTokenFromTheCookiePasses() throws Exception {
        Cookie token = firstAnswer().getCookie(AntiForgery.COOKIE);

        mockMvc.perform(post("/probe/closed")
                        .with(user("1"))
                        .cookie(token)
                        .header(AntiForgery.HEADER, token.getValue()))
                .andExpect(status().isOk());
    }

    @Test
    void aVisitorWithTheTokenButWithoutSignInIsToldToSignIn() throws Exception {
        mockMvc.perform(post("/probe/closed").with(AntiForgery.token()))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("auth.unauthenticated"));
    }

    @Test
    void theFirstAnswerCarriesTheTokenInACookieThatOnlyThisSiteGetsBack() throws Exception {
        Cookie token = firstAnswer().getCookie(AntiForgery.COOKIE);

        assertThat(token).isNotNull();
        assertThat(token.getValue()).isNotBlank();
        assertThat(token.getAttribute("SameSite")).isEqualTo("Strict");
        assertThat(token.getSecure()).isTrue();
        // The front end has to read the token, so this cookie is not hidden from scripts.
        assertThat(token.isHttpOnly()).isFalse();
    }

    @Test
    void aRequestThatAlreadyHasTheTokenGetsNoNewOne() throws Exception {
        Cookie token = firstAnswer().getCookie(AntiForgery.COOKIE);

        MockHttpServletResponse next = mockMvc.perform(get("/api/v1/languages").cookie(token))
                .andReturn()
                .getResponse();

        assertThat(next.getCookie(AntiForgery.COOKIE)).isNull();
    }

    private MockHttpServletResponse firstAnswer() throws Exception {
        return mockMvc.perform(get("/api/v1/languages"))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse();
    }

    // Exists only in this test: one address from the open list and one outside it.
    @RestController
    static class ProbeController {

        @GetMapping("/api/v1/languages")
        String open() {
            return "open";
        }

        @GetMapping("/probe/closed")
        String closed() {
            return "closed";
        }

        @PostMapping("/probe/closed")
        String change() {
            return "changed";
        }
    }
}
