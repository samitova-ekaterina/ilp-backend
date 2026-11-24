package io.github.samitovaekaterina.ilp.reference.model;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import io.github.samitovaekaterina.ilp.IntegrationTestBase;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.hibernate.proxy.HibernateProxy;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

class LanguageMappingIT extends IntegrationTestBase {

    @PersistenceContext
    private EntityManager entityManager;

    @Autowired
    private PlatformTransactionManager transactionManager;

    private TransactionTemplate transaction;

    @BeforeEach
    void prepareTheTransaction() {
        transaction = new TransactionTemplate(transactionManager);
    }

    @Test
    void aChangedLanguageDoesNotReachTheDatabase() {
        transaction.executeWithoutResult(status -> {
            Language english = english();
            // The class has no way to change a language, so the test changes the field directly.
            ReflectionTestUtils.setField(english, "name", "Changed");
            entityManager.flush();
        });

        assertThat(storedNameOfEnglish()).isEqualTo("English");
    }

    @Test
    void aQueryThatChangesLanguagesIsRejected() {
        assertThatThrownBy(() -> transaction.executeWithoutResult(status -> entityManager
                        .createQuery("update Language l set l.name = 'Changed'")
                        .executeUpdate()))
                .isInstanceOf(RuntimeException.class);

        assertThat(storedNameOfEnglish()).isEqualTo("English");
    }

    @Test
    void theStandInObjectOfHibernateEqualsTheLoadedRow() {
        Language loaded = transaction.execute(status -> english());

        transaction.executeWithoutResult(status -> {
            Language standIn = entityManager.getReference(Language.class, loaded.getId());

            assertThat(standIn).isInstanceOf(HibernateProxy.class).isNotSameAs(loaded);
            assertThat(standIn.equals(loaded)).isTrue();
            assertThat(loaded.equals(standIn)).isTrue();
            assertThat(standIn.hashCode()).isEqualTo(loaded.hashCode());
        });
    }

    private Language english() {
        return entityManager
                .createQuery("select l from Language l where l.code = 'en'", Language.class)
                .getSingleResult();
    }

    private String storedNameOfEnglish() {
        return asOwner().queryForObject("SELECT name FROM core.language WHERE code = 'en'", String.class);
    }
}
