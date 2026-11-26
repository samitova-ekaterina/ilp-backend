package io.github.samitovaekaterina.ilp;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationContext;
import org.springframework.security.core.userdetails.UserDetailsService;

class IlpApplicationIT extends IntegrationTestBase {

    @Autowired
    private ApplicationContext context;

    @Test
    void contextLoads() {}

    @Test
    void springSecurityCreatesNoUserOfItsOwn() {
        assertThat(context.getBeansOfType(UserDetailsService.class)).isEmpty();
    }
}
