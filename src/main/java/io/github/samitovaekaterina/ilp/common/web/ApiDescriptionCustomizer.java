package io.github.samitovaekaterina.ilp.common.web;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.Operation;
import io.swagger.v3.oas.models.PathItem;
import io.swagger.v3.oas.models.headers.Header;
import io.swagger.v3.oas.models.media.Content;
import io.swagger.v3.oas.models.media.MediaType;
import io.swagger.v3.oas.models.media.Schema;
import io.swagger.v3.oas.models.responses.ApiResponse;
import java.util.List;
import org.springdoc.core.customizers.GlobalOpenApiCustomizer;
import org.springframework.stereotype.Component;

/** Adds to the API description what every answer of the server has: the request number and the body of an error. */
@Component
public class ApiDescriptionCustomizer implements GlobalOpenApiCustomizer {

    static final String ERROR_SCHEMA = "Problem";

    static final String ERROR_MEDIA_TYPE = "application/problem+json";

    @Override
    public void customise(OpenAPI openApi) {
        if (openApi.getComponents() == null) {
            openApi.setComponents(new Components());
        }
        openApi.getComponents().addSchemas(ERROR_SCHEMA, errorSchema());
        for (PathItem path : openApi.getPaths().values()) {
            for (Operation operation : path.readOperations()) {
                // "default" stands for every status that has no description of its own: all errors share one body.
                operation.getResponses().addApiResponse("default", errorResponse());
                operation
                        .getResponses()
                        .values()
                        .forEach(response -> response.addHeaderObject(RequestIdFilter.HEADER, requestIdHeader()));
            }
        }
    }

    private static ApiResponse errorResponse() {
        Schema<?> reference = new Schema<>().$ref("#/components/schemas/" + ERROR_SCHEMA);
        return new ApiResponse()
                .description("Any error. The body is the same for every status.")
                .content(new Content().addMediaType(ERROR_MEDIA_TYPE, new MediaType().schema(reference)));
    }

    private static Header requestIdHeader() {
        return new Header()
                .description("The number the server gave to this request. The log lines of the request carry it too.")
                .required(true)
                .schema(typed("string"));
    }

    private static Schema<?> errorSchema() {
        Schema<?> violation = typed("object");
        violation.addProperty("field", typed("string").description("The form field or request parameter to correct."));
        violation.addProperty("code", typed("string").description("The permanent name of the reason."));
        violation.setRequired(List.of("field", "code"));

        Schema<?> errors = typed("array").description("Only when the input is invalid: what to correct.");
        errors.setItems(violation);

        Schema<?> problem = typed("object");
        problem.addProperty("title", typed("string"));
        problem.addProperty("status", typed("integer").description("The HTTP status of the answer."));
        problem.addProperty("detail", typed("string"));
        problem.addProperty("instance", typed("string"));
        problem.addProperty("code", typed("string").description("The permanent name of the error."));
        problem.addProperty("requestId", typed("string").description("The same number as in the X-Request-Id header."));
        problem.addProperty("errors", errors);
        problem.setRequired(List.of("title", "status", "detail", "code", "requestId"));
        return problem;
    }

    // Both ways of naming the type are set: version 3.1 of the description format reads one, version 3.0 the other.
    private static Schema<?> typed(String type) {
        Schema<?> schema = new Schema<>();
        schema.setType(type);
        schema.addType(type);
        return schema;
    }
}
