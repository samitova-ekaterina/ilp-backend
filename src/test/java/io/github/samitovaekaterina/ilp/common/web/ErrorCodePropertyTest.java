package io.github.samitovaekaterina.ilp.common.web;

import static org.assertj.core.api.Assertions.assertThat;

import net.jqwik.api.ForAll;
import net.jqwik.api.Property;
import net.jqwik.api.constraints.IntRange;
import org.springframework.http.HttpStatusCode;

class ErrorCodePropertyTest {

    @Property
    void everyErrorStatusGetsANameOfItsOwnFamily(@ForAll @IntRange(min = 400, max = 599) int status) {
        ErrorCode errorCode = ErrorCode.forStatus(HttpStatusCode.valueOf(status));

        assertThat(errorCode.getStatus().is5xxServerError()).isEqualTo(status >= 500);
    }

    // Several names may share a status, so the name may differ, but never the status.
    @Property
    void aStatusWithANameOfItsOwnKeepsItsStatus(@ForAll ErrorCode errorCode) {
        assertThat(ErrorCode.forStatus(errorCode.getStatus()).getStatus()).isEqualTo(errorCode.getStatus());
    }
}
