package io.github.samitovaekaterina.ilp;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.methods;
import static com.tngtech.archunit.library.Architectures.layeredArchitecture;

import com.tngtech.archunit.core.domain.Dependency;
import com.tngtech.archunit.core.domain.JavaClass;
import com.tngtech.archunit.core.domain.JavaClasses;
import com.tngtech.archunit.core.domain.JavaMethod;
import com.tngtech.archunit.core.importer.ClassFileImporter;
import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.lang.ArchCondition;
import com.tngtech.archunit.lang.ConditionEvents;
import com.tngtech.archunit.lang.SimpleConditionEvent;
import org.junit.jupiter.api.Test;
import org.springframework.web.bind.annotation.RestController;

class ArchitectureTest {

    private static final String ROOT = "io.github.samitovaekaterina.ilp";

    private static final JavaClasses CODE = new ClassFileImporter()
            .withImportOption(ImportOption.Predefined.DO_NOT_INCLUDE_TESTS)
            .importPackages(ROOT);

    @Test
    void layersDependOnlyDownwards() {
        layeredArchitecture()
                .consideringOnlyDependenciesInLayers()
                .layer("web")
                .definedBy("..web..")
                .layer("service")
                .definedBy("..service..")
                .layer("repository")
                .definedBy("..repository..")
                .layer("model")
                .definedBy("..model..")
                .whereLayer("web")
                .mayNotBeAccessedByAnyLayer()
                .whereLayer("service")
                .mayOnlyBeAccessedByLayers("web")
                .whereLayer("repository")
                .mayOnlyBeAccessedByLayers("service")
                .whereLayer("model")
                .mayOnlyBeAccessedByLayers("web", "service", "repository")
                .check(CODE);
    }

    @Test
    void moduleUsesAnotherModuleOnlyThroughItsService() {
        classes()
                .that()
                .resideInAPackage(ROOT + ".*..")
                .should(reachOtherModulesOnlyThroughTheirService())
                .check(CODE);
    }

    @Test
    void controllersDoNotReturnTableClasses() {
        methods()
                .that()
                .areDeclaredInClassesThat()
                .areAnnotatedWith(RestController.class)
                .should(notReturnTableClasses())
                .check(CODE);
    }

    private static String moduleOf(JavaClass javaClass) {
        String name = javaClass.getPackageName();
        return name.startsWith(ROOT + ".") ? name.substring(ROOT.length() + 1).split("\\.")[0] : null;
    }

    private static ArchCondition<JavaClass> reachOtherModulesOnlyThroughTheirService() {
        return new ArchCondition<>("reach other modules only through their service") {
            @Override
            public void check(JavaClass origin, ConditionEvents events) {
                String module = moduleOf(origin);
                for (Dependency dependency : origin.getDirectDependenciesFromSelf()) {
                    String other = moduleOf(dependency.getTargetClass());
                    if (other == null || other.equals(module) || other.equals("common")) {
                        continue;
                    }
                    boolean throughService =
                            dependency.getTargetClass().getPackageName().startsWith(ROOT + "." + other + ".service");
                    if (module.equals("common") || !throughService) {
                        events.add(SimpleConditionEvent.violated(dependency, dependency.getDescription()));
                    }
                }
            }
        };
    }

    private static ArchCondition<JavaMethod> notReturnTableClasses() {
        return new ArchCondition<>("not return table classes") {
            @Override
            public void check(JavaMethod method, ConditionEvents events) {
                for (JavaClass type : method.getReturnType().getAllInvolvedRawTypes()) {
                    if (type.getPackageName().endsWith(".model")) {
                        events.add(SimpleConditionEvent.violated(
                                method, method.getFullName() + " returns the table class " + type.getName()));
                    }
                }
            }
        };
    }
}
