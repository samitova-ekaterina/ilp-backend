package io.github.samitovaekaterina.ilp;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.info.Info;

@SpringBootApplication
@OpenAPIDefinition(info = @Info(title = "ILP API", version = "v1",
		description = "Interactive learning from PDF materials: exercises and adaptive spaced repetition."))
public class IlpApplication {

	public static void main(String[] args) {
		SpringApplication.run(IlpApplication.class, args);
	}

}
