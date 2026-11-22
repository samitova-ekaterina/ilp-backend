package io.github.samitovaekaterina.ilp.common.web;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import net.jqwik.api.ForAll;
import net.jqwik.api.Property;
import net.jqwik.api.constraints.LowerChars;
import net.jqwik.api.constraints.Size;
import net.jqwik.api.constraints.StringLength;
import org.springframework.context.support.DefaultMessageSourceResolvable;

class FieldViolationPropertyTest {

    @Property
    void wordsOfTheRuleNameAreJoinedWithHyphens(
            @ForAll @Size(min = 1, max = 5) List<@LowerChars @StringLength(min = 2, max = 8) String> words,
            @ForAll boolean startsWithCapital) {
        String rule = camelCase(words, startsWithCapital);

        String code = FieldViolation.of("field", new DefaultMessageSourceResolvable(new String[] {rule}, rule))
                .code();

        assertThat(code).isEqualTo(String.join("-", words));
    }

    private static String camelCase(List<String> words, boolean startsWithCapital) {
        StringBuilder name = new StringBuilder();
        for (int i = 0; i < words.size(); i++) {
            String word = words.get(i);
            boolean capital = i > 0 || startsWithCapital;
            name.append(capital ? Character.toUpperCase(word.charAt(0)) + word.substring(1) : word);
        }
        return name.toString();
    }
}
