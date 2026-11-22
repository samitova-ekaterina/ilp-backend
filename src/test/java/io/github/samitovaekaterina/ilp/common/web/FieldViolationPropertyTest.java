package io.github.samitovaekaterina.ilp.common.web;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Locale;
import net.jqwik.api.ForAll;
import net.jqwik.api.Property;
import net.jqwik.api.constraints.AlphaChars;
import net.jqwik.api.constraints.StringLength;
import org.springframework.context.support.DefaultMessageSourceResolvable;

class FieldViolationPropertyTest {

    @Property
    void theNameOfARuleBecomesLowerCaseWithHyphens(@ForAll @AlphaChars @StringLength(min = 1, max = 40) String rule) {
        String code = FieldViolation.of("field", new DefaultMessageSourceResolvable(new String[] {rule}, rule))
                .code();

        assertThat(code).isEqualTo(code.toLowerCase(Locale.ROOT));
        assertThat(code).doesNotStartWith("-").doesNotEndWith("-").doesNotContain("--");
        assertThat(code.replace("-", "")).isEqualTo(rule.toLowerCase(Locale.ROOT));
    }
}
