package io.github.samitovaekaterina.ilp.reference.repository;

import java.util.List;

import org.springframework.data.repository.Repository;

import io.github.samitovaekaterina.ilp.reference.model.Language;

public interface LanguageRepository extends Repository<Language, Long> {

	List<Language> findAllByOrderByNameAsc();

}
