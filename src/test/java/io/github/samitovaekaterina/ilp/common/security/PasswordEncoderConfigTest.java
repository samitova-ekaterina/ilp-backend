package io.github.samitovaekaterina.ilp.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.crypto.argon2.Argon2PasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

// The settings come from application.yaml, as in the running application; no database is started.
@SpringBootTest(classes = PasswordEncoderConfig.class, webEnvironment = SpringBootTest.WebEnvironment.NONE)
class PasswordEncoderConfigTest {

    // The hash of the test users from the migration 0026; their password is published in the README.
    private static final String HASH_OF_THE_TEST_USERS =
            "$argon2id$v=19$m=19456,t=2,p=1$W2CQPCVHMunNXR+YhQyasA$JDdjiumyd8JqOUUaTYtCt6URQDlncQ75bbDkqFd7JdM";

    private static final String PASSWORD = "a long phrase of several words";

    @Autowired
    private PasswordEncoder encoder;

    @Test
    void aNewHashHasTheFormDescribedInTheDatabaseDocumentation() {
        String hash = encoder.encode(PASSWORD);

        assertThat(hash).matches("\\$argon2id\\$v=19\\$m=19456,t=2,p=1\\$[A-Za-z0-9+/]{22}\\$[A-Za-z0-9+/]{43}");
    }

    @Test
    void aNewHashMatchesItsPassword() {
        assertThat(encoder.matches(PASSWORD, encoder.encode(PASSWORD))).isTrue();
    }

    @Test
    void everyHashHasItsOwnSalt() {
        assertThat(encoder.encode(PASSWORD)).isNotEqualTo(encoder.encode(PASSWORD));
    }

    @Test
    void thePasswordOfTheTestUsersMatchesTheirHashFromTheMigration() {
        assertThat(encoder.matches("TestPassword1", HASH_OF_THE_TEST_USERS)).isTrue();
    }

    @Test
    void aWrongPasswordDoesNotMatch() {
        assertThat(encoder.matches("TestPassword2", HASH_OF_THE_TEST_USERS)).isFalse();
    }

    @Test
    void aHashMadeWithWeakerSettingsStillMatchesAndIsToBeReplaced() {
        String weaker = new Argon2PasswordEncoder(16, 32, 1, 4096, 1).encode(PASSWORD);

        assertThat(encoder.matches(PASSWORD, weaker)).isTrue();
        assertThat(encoder.upgradeEncoding(weaker)).isTrue();
    }

    @Test
    void aHashMadeWithTheCurrentSettingsIsKept() {
        assertThat(encoder.upgradeEncoding(HASH_OF_THE_TEST_USERS)).isFalse();
    }
}
