package io.github.samitovaekaterina.ilp.common.web;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.context.MessageSourceResolvable;
import org.springframework.context.support.DefaultMessageSourceResolvable;

class FieldViolationTest {

    @Test
    void reasonIsTheNameOfTheBrokenRuleInKebabCase() {
        MessageSourceResolvable error =
                new DefaultMessageSourceResolvable(new String[] {"NotBlank.form.name", "NotBlank"});

        FieldViolation violation = FieldViolation.of("name", error);

        assertThat(violation).isEqualTo(new FieldViolation("name", "not-blank"));
    }

    @Test
    void errorWithoutCodesGetsTheGeneralReason() {
        MessageSourceResolvable error = new DefaultMessageSourceResolvable(new String[0]);

        FieldViolation violation = FieldViolation.of("name", error);

        assertThat(violation.code()).isEqualTo("invalid");
    }
}
