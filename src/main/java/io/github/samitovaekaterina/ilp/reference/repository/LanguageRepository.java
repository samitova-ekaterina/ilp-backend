package io.github.samitovaekaterina.ilp.reference.repository;

import io.github.samitovaekaterina.ilp.reference.model.Language;
import java.util.List;
import org.springframework.data.repository.Repository;

public interface LanguageRepository extends Repository<Language, Long> {

    List<Language> findAllByOrderByNameAsc();
}
