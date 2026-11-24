package io.github.samitovaekaterina.ilp.common.model;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.HashSet;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

class BaseEntityTest {

    @Test
    void twoObjectsOfTheSameRowAreEqual() {
        Word first = saved(new Word(), 7L);
        Word second = saved(new Word(), 7L);

        assertThat(first).isEqualTo(second).hasSameHashCodeAs(second);
    }

    @Test
    void objectsOfDifferentRowsAreNotEqual() {
        assertThat(saved(new Word(), 7L)).isNotEqualTo(saved(new Word(), 8L));
    }

    @Test
    void twoObjectsThatAreNotSavedYetAreNotEqual() {
        assertThat(new Word()).isNotEqualTo(new Word());
    }

    @Test
    void anObjectThatIsNotSavedYetIsEqualToItself() {
        Word word = new Word();

        assertThat(word).isEqualTo(word);
    }

    @Test
    void aSavedObjectIsNotEqualToOneThatIsNotSavedYet() {
        assertThat(saved(new Word(), 7L)).isNotEqualTo(new Word());
    }

    @Test
    void theSameRowNumberInAnotherTableIsNotTheSameRow() {
        assertThat(saved(new Word(), 7L)).isNotEqualTo(saved(new Note(), 7L));
    }

    @Test
    void anObjectIsNotEqualToNothingAndToAThingOfAnotherKind() {
        Word word = saved(new Word(), 7L);

        assertThat(word).isNotEqualTo(null).isNotEqualTo("7");
    }

    @Test
    void savingDoesNotLoseTheObjectInASet() {
        Word word = new Word();
        Set<Word> words = new HashSet<>();
        words.add(word);

        saved(word, 7L);

        assertThat(words).contains(word);
    }

    private static <T extends BaseEntity> T saved(T object, long id) {
        // The database gives the id, so the class has no way to set it.
        ReflectionTestUtils.setField(object, "id", id);
        return object;
    }

    static class Word extends BaseEntity {}

    static class Note extends BaseEntity {}
}
