# Checks of the libraries

Every library the application is shipped with is checked in two ways. Both checks run on every push; the licence check also runs locally as a part of `./gradlew check`.

## Licences

`./gradlew checkLicense` builds the report of the licences of all libraries on the runtime classpath and compares it with the list in [`config/allowed-licenses.json`](../config/allowed-licenses.json). A library with a licence that is not on the list fails the build. The report is written to `build/reports/dependency-license/index.html`.

The list follows one rule with three groups:

| Group | Licences | Rule |
|---|---|---|
| Permissive | Apache 2.0, MIT, BSD, ISC | Allowed |
| Weak copyleft and FSL | EPL, LGPL, MPL, FSL | Allowed only as a ready-made library: its code is not changed and not copied into the project |
| Strong copyleft | GPL, AGPL | Not allowed |

No paid library is used. A new licence is added to the list only after it is placed in one of the groups.

## Known vulnerabilities

The workflow builds the application file and scans the libraries packed inside it with Trivy. A vulnerability of the critical level fails the run. The run also fails when Trivy reads fewer than 50 libraries: this means that it did not look inside the application file. The number of libraries it read is printed in the log of the run. The version of Trivy is fixed in `.github/workflows/checks.yml`.
