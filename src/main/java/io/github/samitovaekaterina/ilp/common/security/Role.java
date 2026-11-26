package io.github.samitovaekaterina.ilp.common.security;

public enum Role {
    TEACHER,
    LEARNER;

    // Spring Security tells a role from other rights by this prefix.
    public String authority() {
        return "ROLE_" + name();
    }
}
