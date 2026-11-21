package io.github.samitovaekaterina.ilp;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@ExtendWith(OutputCaptureExtension.class)
class RequestLogIT {

	@Autowired
	private MockMvc mockMvc;

	@Test
	void unknownAddressIsNotWrittenToTheLog(CapturedOutput output) throws Exception {
		mockMvc.perform(get("/api/v1/users/anna@example.com")).andExpect(status().isNotFound());
		assertThat(output).contains("GET unmatched -> 404").doesNotContain("anna@example.com");
	}

}
