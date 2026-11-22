package io.github.samitovaekaterina.ilp.common.web;

import static org.assertj.core.api.Assertions.assertThat;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.Operation;
import io.swagger.v3.oas.models.PathItem;
import io.swagger.v3.oas.models.Paths;
import io.swagger.v3.oas.models.media.Schema;
import io.swagger.v3.oas.models.responses.ApiResponse;
import io.swagger.v3.oas.models.responses.ApiResponses;
import org.junit.jupiter.api.Test;

class ApiDescriptionCustomizerTest {

    private final ApiDescriptionCustomizer customizer = new ApiDescriptionCustomizer();

    @Test
    void everyAnswerGetsTheRequestNumberHeader() {
        OpenAPI description = descriptionWithOneOperation();

        customizer.customise(description);

        ApiResponses answers = answersOfTheOperation(description);
        assertThat(answers.get("200").getHeaders()).containsOnlyKeys("X-Request-Id");
        assertThat(answers.get("default").getHeaders()).containsOnlyKeys("X-Request-Id");
        assertThat(answers.get("200").getHeaders().get("X-Request-Id").getRequired())
                .isTrue();
        assertThat(answers.get("default").getHeaders().get("X-Request-Id").getRequired())
                .isTrue();
        Schema<?> header = answers.get("200").getHeaders().get("X-Request-Id").getSchema();
        assertThat(header.getTypes()).containsExactly("string");
    }

    @Test
    void everyOperationGetsTheCommonErrorAnswer() {
        OpenAPI description = descriptionWithOneOperation();

        customizer.customise(description);

        ApiResponse error = answersOfTheOperation(description).get("default");
        assertThat(error.getContent()).containsOnlyKeys("application/problem+json");
        assertThat(error.getContent()
                        .get("application/problem+json")
                        .getSchema()
                        .get$ref())
                .isEqualTo("#/components/schemas/Problem");
    }

    @Test
    void theErrorSchemaListsTheFieldsOfTheErrorBody() {
        OpenAPI description = descriptionWithOneOperation();

        customizer.customise(description);

        Schema<?> problem = description.getComponents().getSchemas().get("Problem");
        assertThat(problem.getProperties())
                .containsOnlyKeys("title", "status", "detail", "instance", "code", "requestId", "errors");
        assertThat(problem.getRequired()).containsExactlyInAnyOrder("title", "status", "detail", "code", "requestId");
        Schema<?> status = problem.getProperties().get("status");
        assertThat(status.getType()).isEqualTo("integer");
        assertThat(status.getTypes()).containsExactly("integer");

        Schema<?> errors = problem.getProperties().get("errors");
        assertThat(errors.getTypes()).containsExactly("array");
        assertThat(errors.getItems().getProperties()).containsOnlyKeys("field", "code");
        assertThat(errors.getItems().getRequired()).containsExactlyInAnyOrder("field", "code");
    }

    private static OpenAPI descriptionWithOneOperation() {
        ApiResponses answers = new ApiResponses().addApiResponse("200", new ApiResponse().description("OK"));
        return new OpenAPI()
                .paths(new Paths().addPathItem("/items", new PathItem().get(new Operation().responses(answers))));
    }

    private static ApiResponses answersOfTheOperation(OpenAPI description) {
        return description.getPaths().get("/items").getGet().getResponses();
    }
}
