package io.github.samitovaekaterina.ilp.common.web;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

class GlobalExceptionHandlerTest {

	private final MockMvc mockMvc = MockMvcBuilders.standaloneSetup(new ProbeController())
		.setControllerAdvice(new GlobalExceptionHandler())
		.build();

	@Test
	void invalidInputReturns400InTheCommonFormat() throws Exception {
		mockMvc.perform(get("/probe/items/not-a-number"))
			.andExpect(status().isBadRequest())
			.andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
			.andExpect(jsonPath("$.status").value(400))
			.andExpect(jsonPath("$.code").value("common.bad-request"));
	}

	@Test
	void unexpectedFailureReturns500WithoutInternalDetails() throws Exception {
		mockMvc.perform(get("/probe/failure"))
			.andExpect(status().isInternalServerError())
			.andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
			.andExpect(jsonPath("$.code").value("common.internal-error"))
			.andExpect(jsonPath("$.detail").value(ErrorCode.INTERNAL_ERROR.getDetail()))
			.andExpect(content().string(not(containsString("secret reason"))));
	}

	// Exists only in this test: the application has no request yet that can fail on demand.
	@RestController
	static class ProbeController {

		@GetMapping("/probe/items/{id}")
		String item(@PathVariable("id") long id) {
			return "item " + id;
		}

		@GetMapping("/probe/failure")
		String failure() {
			throw new IllegalStateException("secret reason");
		}

	}

}
