package io.github.samitovaekaterina.ilp.common.web;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

class ErrorCodeTest {

    @Test
    void knownStatusGivesItsOwnCode() {
        ErrorCode code = ErrorCode.forStatus(HttpStatus.NOT_FOUND);

        assertThat(code).isEqualTo(ErrorCode.NOT_FOUND);
    }

    @Test
    void aStatusWithSeveralNamesGivesItsGeneralName() {
        ErrorCode code = ErrorCode.forStatus(HttpStatus.FORBIDDEN);

        assertThat(code).isEqualTo(ErrorCode.FORBIDDEN);
    }

    @Test
    void theRefusalsOfSignInAndAccessHaveTheirOwnNames() {
        assertThat(ErrorCode.UNAUTHENTICATED.getCode()).isEqualTo("auth.unauthenticated");
        assertThat(ErrorCode.UNAUTHENTICATED.getStatus()).isEqualTo(HttpStatus.UNAUTHORIZED);
        assertThat(ErrorCode.FORBIDDEN.getCode()).isEqualTo("auth.forbidden");
        assertThat(ErrorCode.CSRF.getCode()).isEqualTo("auth.csrf");
        assertThat(ErrorCode.CSRF.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
    }

    @Test
    void otherClientErrorCountsAsBadRequest() {
        ErrorCode code = ErrorCode.forStatus(HttpStatus.NOT_ACCEPTABLE);

        assertThat(code).isEqualTo(ErrorCode.BAD_REQUEST);
    }

    @Test
    void otherServerErrorCountsAsInternalError() {
        ErrorCode code = ErrorCode.forStatus(HttpStatus.SERVICE_UNAVAILABLE);

        assertThat(code).isEqualTo(ErrorCode.INTERNAL_ERROR);
    }

    @Test
    void everyErrorHasItsOwnName() {
        assertThat(ErrorCode.values()).extracting(ErrorCode::getCode).doesNotHaveDuplicates();
    }
}
