package io.github.samitovaekaterina.ilp.reference.service;

import java.util.List;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import io.github.samitovaekaterina.ilp.reference.model.Language;
import io.github.samitovaekaterina.ilp.reference.repository.LanguageRepository;

@Service
@Transactional(readOnly = true)
public class LanguageServiceImpl implements LanguageService {

	private final LanguageRepository languageRepository;

	public LanguageServiceImpl(LanguageRepository languageRepository) {
		this.languageRepository = languageRepository;
	}

	@Override
	public List<Language> findAll() {
		return languageRepository.findAllByOrderByNameAsc();
	}

}
