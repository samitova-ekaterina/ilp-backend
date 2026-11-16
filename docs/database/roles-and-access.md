# Roles and access

Access to the database is built on one idea: nobody works with more rights than the task needs. The application does not run as a superuser, the account that changes the structure is not the account the application uses, and a reader of data does not see personal data.

## Three roles

The roles are groups of rights. They cannot log in and have no passwords; a real account receives rights by becoming a member of a role. Their names start with `ilp_`, because roles in PostgreSQL belong to the whole server and not to one database.

| Role | For whom | May | May not |
|---|---|---|---|
| `ilp_read` | Reports, support, analysis | Read 51 of the 57 tables in full, and the remaining six without their protected columns or not at all; read the views | Change anything; read e-mail addresses, names, password hashes, texts of notes, invitation and summary codes, or the table that links a learning link to its statistics code |
| `ilp_write` | The application | Read everything; insert, update and delete rows in the 45 working tables; insert statistics events; run the procedures of erasure, clean-up and summary refresh | Change the 11 reference tables; update or delete statistics events; create or alter tables |
| `ilp_admin` | Migrations and administration | Everything in both schemas, including creating objects; receives rights on future tables automatically | — |

The reasons behind the three limits of the writing role are these. Reference tables are filled by migrations, so their content is versioned together with the structure and cannot be changed by a mistake in the application. A statistics event is written once and never corrected, which is what makes the statistics trustworthy. And the application has no reason to manage the structure at all.

### What the reading role does not see

| Table | Hidden from `ilp_read` | What it gets instead |
|---|---|---|
| `core.app_user` | `email`, `display_name`, `password_hash` | The view `core.v_app_user_masked` with masked values |
| `core.note` | `note_text` | The view `core.v_note_masked` with the length of the text |
| `core.erasure_request` | `confirmation_code_hash` | The other columns |
| `core.invitation` | `code` | The other columns |
| `core.summary_link` | `code` | The other columns |
| `core.learning_link_pseudonym` | The whole table | Nothing: it is the key that connects statistics to a person |

The protection is made of column-level rights, not of a convention: a query from the reading role that names a hidden column fails with "permission denied". Masking is described in [personal-data.md](personal-data.md).

### Rights on new objects

The reading and the writing role receive no rights on a new table by themselves. Each migration that creates a table, a view or a procedure grants the rights in the same file, so the decision who may see a new object is made at the moment the object appears and is reviewed with it. Migration `0037`, which adds three tables for pronunciation, and migrations `0041`-`0049`, which add views and procedures, follow this rule.

Functions and procedures in PostgreSQL may be executed by everyone unless this right is taken away. The three procedures that change data have it revoked from `PUBLIC` and granted to `ilp_write` and `ilp_admin` only.

## Accounts

| Account | What it is | Where its password lives |
|---|---|---|
| `ilp_owner` | Owns the database and runs migrations. Member of `ilp_admin`. Has the attribute `CREATEROLE`, because the roles are created by a migration | Only in the environment variable `LIQUIBASE_COMMAND_PASSWORD` |
| `ilp_app` | The account of the application. Member of `ilp_write` and nothing else, not a superuser | Outside the repository; the back end reads it from an environment variable |
| `postgres` | The administrator of the server | Used only to create the database and the two accounts |

No password, key or connection string with a password is stored in the repository. The file `liquibase.properties` contains the address of the database and the name of the account, and nothing secret.

## Passwords of users

A password of a user is never stored. The column `app_user.password_hash` holds an Argon2id hash with the parameters recommended by the OWASP Password Storage Cheat Sheet: 19 MiB of memory (`m=19456`), two iterations (`t=2`) and one thread (`p=1`). Outdated functions such as MD5 and SHA-1 are not used anywhere.

The hash is stored as a single string of the form `$argon2id$v=19$m=19456,t=2,p=1$salt$hash`. The string names the algorithm, its parameters and the salt, so every password has its own salt and the parameters can be strengthened later without changing the column: an old hash remains verifiable and can be replaced with a stronger one at the next login.

The same approach is used for the confirmation code of an erasure request. The code itself is sent by e-mail, the database keeps only its hash in `erasure_request.confirmation_code_hash`, and the hash is cleared when the request is executed.

## How the rights were checked

The rights were tested on a database with test data by switching to each role and trying both the allowed and the forbidden action: the reading role reading a hidden column, inserting a row and calling a procedure; the writing role changing a reference table and updating a statistics event. Every forbidden action was refused by the database.
