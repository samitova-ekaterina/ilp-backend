package io.github.samitovaekaterina.ilp.reference.web;

import java.util.List;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import io.github.samitovaekaterina.ilp.reference.service.LanguageService;

@RestController
@RequestMapping("/api/v1/languages")
public class LanguageController {

	private final LanguageService languageService;

	public LanguageController(LanguageService languageService) {
		this.languageService = languageService;
	}

	@GetMapping
	public List<LanguageResponse> findAll() {
		return languageService.findAll().stream().map(LanguageResponse::from).toList();
	}

}
