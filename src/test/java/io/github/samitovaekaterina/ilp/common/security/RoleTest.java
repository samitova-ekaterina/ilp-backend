package io.github.samitovaekaterina.ilp.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class RoleTest {

    @Test
    void everyRoleIsARoleForSpringSecurity() {
        assertThat(Role.TEACHER.authority()).isEqualTo("ROLE_TEACHER");
        assertThat(Role.LEARNER.authority()).isEqualTo("ROLE_LEARNER");
    }

    @Test
    void everyRoleHasItsOwnName() {
        assertThat(Role.values()).extracting(Role::authority).doesNotHaveDuplicates();
    }
}
