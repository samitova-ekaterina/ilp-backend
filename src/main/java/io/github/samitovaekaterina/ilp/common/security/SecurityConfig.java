package io.github.samitovaekaterina.ilp.common.security;

import jakarta.servlet.DispatcherType;
import java.time.Clock;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.context.SecurityContextHolderFilter;
import org.springframework.security.web.csrf.CookieCsrfTokenRepository;
import org.springframework.security.web.savedrequest.NullRequestCache;

@Configuration
@EnableWebSecurity
@EnableConfigurationProperties(SessionSettings.class)
public class SecurityConfig {

    @Bean
    SecurityFilterChain securityFilterChain(
            HttpSecurity http,
            RefusalHandler refusals,
            SessionSettings session,
            Environment environment,
            @Value("${server.servlet.session.cookie.secure}") boolean secureCookies)
            throws Exception {
        boolean developerComputer = environment.acceptsProfiles(Profiles.of(OpenAddresses.DEVELOPER_PROFILE));
        http.authorizeHttpRequests(requests -> {
                    // The error page of the server itself: closed, it would turn every such error into 401.
                    requests.dispatcherTypeMatchers(DispatcherType.ERROR).permitAll();
                    for (OpenAddresses.Address address : OpenAddresses.on(developerComputer)) {
                        requests.requestMatchers(address.method(), address.pattern())
                                .permitAll();
                    }
                    requests.anyRequest().authenticated();
                })
                .csrf(csrf -> csrf.spa().csrfTokenRepository(csrfTokenRepository(secureCookies)))
                .addFilterBefore(
                        new SessionLifetimeFilter(session.sessionLifetime(), Clock.systemUTC()),
                        SecurityContextHolderFilter.class)
                .exceptionHandling(
                        handling -> handling.authenticationEntryPoint(refusals).accessDeniedHandler(refusals))
                // By default a refused request is remembered in a session: every refusal would create one.
                .requestCache(cache -> cache.requestCache(new NullRequestCache()))
                // The ready sign-out would add an address with an answer of its own; ours comes with the sign-in.
                .logout(AbstractHttpConfigurer::disable);
        return http.build();
    }

    private static CookieCsrfTokenRepository csrfTokenRepository(boolean secureCookies) {
        // The front end has to read this cookie, so scripts of the page may see it, unlike the session cookie.
        CookieCsrfTokenRepository repository = CookieCsrfTokenRepository.withHttpOnlyFalse();
        repository.setCookieCustomizer(cookie -> cookie.secure(secureCookies).sameSite("Strict"));
        return repository;
    }
}
