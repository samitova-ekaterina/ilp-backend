package io.github.samitovaekaterina.ilp.common.model;

import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.MappedSuperclass;
import org.hibernate.proxy.HibernateProxy;

/** The parent of every table class: two objects are equal when they stand for the same row. */
@MappedSuperclass
public abstract class BaseEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    public Long getId() {
        return id;
    }

    @Override
    public final boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (other == null || tableClass(this) != tableClass(other)) {
            return false;
        }
        // An object that is not saved yet has no row, so it is equal only to itself.
        return getId() != null && getId().equals(((BaseEntity) other).getId());
    }

    // The same for every object of a class: a hash built on the id would change at the moment of saving.
    @Override
    public final int hashCode() {
        return tableClass(this).hashCode();
    }

    // Hibernate may hand out a stand-in object of a generated subclass instead of the object itself.
    private static Class<?> tableClass(Object object) {
        return object instanceof HibernateProxy proxy
                ? proxy.getHibernateLazyInitializer().getPersistentClass()
                : object.getClass();
    }
}
