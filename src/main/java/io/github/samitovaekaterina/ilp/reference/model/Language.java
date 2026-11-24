package io.github.samitovaekaterina.ilp.reference.model;

import io.github.samitovaekaterina.ilp.common.model.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import org.hibernate.annotations.Immutable;

@Entity
@Immutable
@Table(schema = "core", name = "language")
public class Language extends BaseEntity {

    @Column(nullable = false, unique = true)
    private String code;

    @Column(nullable = false, unique = true)
    private String name;

    protected Language() {}

    public String getCode() {
        return code;
    }

    public String getName() {
        return name;
    }
}
