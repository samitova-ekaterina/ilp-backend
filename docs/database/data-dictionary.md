# Data dictionary

This file is generated from the database catalogue after all migrations (`0001`-`0050`). Table and column descriptions are the comments stored in the database itself (`COMMENT ON`), so the dictionary and the database cannot drift apart: when a migration changes a comment, the dictionary is regenerated.

The database has 57 tables in two schemas: `core` (56 tables, operational data) and `stats` (1 table, anonymous statistics). Views, functions and procedures are described in [database-objects.md](database-objects.md).

## How to read it

- **Type** is the PostgreSQL type. Conventions for types are explained in [architecture-decisions.md](architecture-decisions.md).
- **Null** says whether the column may be empty. What an empty value means is written in the description.
- **Key** marks: `PK` primary key, `FK` foreign key (the target and the action on delete are given), `UQ` the column alone is unique.
- **Constraints** lists every named constraint of the table with its definition. Names follow the pattern `prefix_table__meaning`: `pk_`, `fk_`, `uq_`, `ck_`.
- **Data quality expectations** are the `CHECK`, `UNIQUE` and `NOT NULL` rules: the database rejects a row that breaks them.
- Columns whose description starts with *Personal data* are covered in [personal-data.md](personal-data.md).

## Tables by block

| Block | Tables |
|---|---|
| [Reference data](#reference-data) | `country`, `language`, `cefr_level`, `scale`, `exercise_type`, `exercise_type_compatibility`, `flag_reason`, `error_type`, `policy_version`, `visual_style`, `pronunciation_variant` |
| [Users and access](#users-and-access) | `app_user`, `consent`, `course`, `study_group`, `learning_link`, `group_membership`, `invitation`, `erasure_request`, `export_request`, `summary_link`, `feature_toggle`, `shown_tooltip`, `pronunciation_choice`, `learning_link_pseudonym` |
| [Materials and parsing](#materials-and-parsing) | `folder`, `material`, `parsing_run`, `topic`, `exercise`, `task`, `exercise_dependency`, `flag`, `image`, `presentation_item`, `word`, `word_pronunciation`, `task_target_word`, `exercise_target_word` |
| [Lessons and homework](#lessons-and-homework) | `lesson`, `lesson_exercise`, `homework`, `homework_assignment`, `homework_exercise`, `homework_task` |
| [Practice and revision](#practice-and-revision) | `answer`, `revision_record`, `topic_priority` |
| [History and level](#history-and-level) | `scale_level`, `level_change`, `oral_error`, `note` |
| [Adaptation](#adaptation) | `adaptation_proposal`, `adaptation_proposal_item` |
| [Competitions](#competitions) | `competition`, `competition_participation` |
| [Anonymous statistics (schema stats)](#anonymous-statistics-schema-stats) | `statistics_event` |

## Reference data

Fixed lists filled by migrations. The application only reads them.

### core.country

Country of residence of a user. Defines the age of consent.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `name` | text | no |  | Country name. |
| `code` | text | no | UQ | Two-letter country code, ISO 3166-1 alpha-2. |
| `consent_age` | integer | no |  | Age from which a user can give consent to data processing in this country. |

Constraints:

- `pk_country`: `PRIMARY KEY (id)`
- `uq_country__code`: `UNIQUE (code)`
- `ck_country__code_format`: `CHECK ((code ~ '^[A-Z]{2}$'::text))`
- `ck_country__consent_age_positive`: `CHECK ((consent_age > 0))`

### core.language

Language: studied language or interface language.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `code` | text | no | UQ | Two-letter language code, ISO 639-1, for example en. Never changed or translated. |
| `name` | text | no | UQ | Language name shown to users. |

Constraints:

- `pk_language`: `PRIMARY KEY (id)`
- `uq_language__code`: `UNIQUE (code)`
- `uq_language__name`: `UNIQUE (name)`
- `ck_language__code_format`: `CHECK ((code ~ '^[a-z]{2}$'::text))`

### core.cefr_level

CEFR level: A1, A2, B1 and so on.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `name` | text | no | UQ | CEFR mark, for example A1. |
| `sort_order` | integer | no | UQ | Ordinal number used to compare levels: higher or lower. |

Constraints:

- `pk_cefr_level`: `PRIMARY KEY (id)`
- `uq_cefr_level__name`: `UNIQUE (name)`
- `uq_cefr_level__sort_order`: `UNIQUE (sort_order)`

### core.scale

Skill scale on which a learner level is measured: vocabulary, grammar, writing, speech.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `code` | text | no | UQ | Stable identifier used by the application. Never changed or translated. |
| `name` | text | no | UQ | Scale name shown to users. |
| `display_order` | integer | no | UQ | Position of the scale in the level chart. The order is always the same. |

Constraints:

- `pk_scale`: `PRIMARY KEY (id)`
- `uq_scale__code`: `UNIQUE (code)`
- `uq_scale__display_order`: `UNIQUE (display_order)`
- `uq_scale__name`: `UNIQUE (name)`

### core.exercise_type

Catalogue of exercise types. New types are added as data, without schema changes.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `code` | text | no | UQ | Stable identifier used by the application. Never changed or translated. |
| `name` | text | no | UQ | Type name shown to users. |
| `recognition_features` | jsonb | no |  | Features by which the parser recognises the type in a document. Structure is described in the type catalogue. |
| `display_mode` | text | no |  | How an exercise of this type is shown to the learner. |
| `checking_mode` | text | no |  | How an answer is checked: automatic or reviewer. |
| `reference_response_time_ms` | integer | yes |  | Reference response time in milliseconds. NULL when no reference is set for the type. |
| `body_schema` | jsonb | no |  | Description of the task body structure for this type. Task bodies are validated against it. |

Constraints:

- `pk_exercise_type`: `PRIMARY KEY (id)`
- `uq_exercise_type__code`: `UNIQUE (code)`
- `uq_exercise_type__name`: `UNIQUE (name)`
- `ck_exercise_type__checking_mode`: `CHECK ((checking_mode = ANY (ARRAY['automatic'::text, 'reviewer'::text])))`
- `ck_exercise_type__display_mode`: `CHECK ((display_mode = ANY (ARRAY['choice'::text, 'inline_choice'::text, 'pairs'::text, 'grouping'::text, 'ordering'::text, 'gap_bank'::text, 'image_gap_bank'::text, 'hotspot'::text, 'gap_bank_typed'::text, 'image_gap_bank_typed'::text, 'grouping_typed'::text, 'choice_typed'::text, 'inline_choice_typed'::text, 'pairs_typed'::text, 'text_entry'::text, 'image_text_entry'::text, 'replace_marked'::text, 'find_and_correct'::text, 'table_entry'::text, 'crossword'::text, 'word_search'::text, 'composite'::text, 'extended_text'::text, 'drawing'::text, 'audio_recording'::text])))`
- `ck_exercise_type__reference_time_positive`: `CHECK ((reference_response_time_ms > 0))`

### core.exercise_type_compatibility

Which exercise type can be converted into which other type.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `source_type_id` | bigint | no | FK → `core.exercise_type`, on delete CASCADE | Type the exercise has. |
| `target_type_id` | bigint | no | FK → `core.exercise_type`, on delete CASCADE | Type the exercise can be converted into. |
| `is_harder` | boolean | no |  | True when the target type is harder than the source type. |

Constraints:

- `pk_exercise_type_compatibility`: `PRIMARY KEY (id)`
- `uq_exercise_type_compatibility__pair`: `UNIQUE (source_type_id, target_type_id)`
- `fk_exercise_type_compatibility__source_type`: `FOREIGN KEY (source_type_id) REFERENCES core.exercise_type(id) ON DELETE CASCADE`
- `fk_exercise_type_compatibility__target_type`: `FOREIGN KEY (target_type_id) REFERENCES core.exercise_type(id) ON DELETE CASCADE`
- `ck_exercise_type_compatibility__different_types`: `CHECK ((source_type_id <> target_type_id))`

### core.flag_reason

Reason why a place in parsed material is flagged for the author to confirm.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `code` | text | no | UQ | Stable identifier used by the application. Never changed or translated. |
| `name` | text | no | UQ | Reason shown to the author next to the flagged place. |

Constraints:

- `pk_flag_reason`: `PRIMARY KEY (id)`
- `uq_flag_reason__code`: `UNIQUE (code)`
- `uq_flag_reason__name`: `UNIQUE (name)`

### core.error_type

Kind of mistake in a learner answer: spelling, form, word choice, comprehension.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `code` | text | no | UQ | Stable identifier used by the application. Never changed or translated. |
| `name` | text | no | UQ | Type name shown to users. |

Constraints:

- `pk_error_type`: `PRIMARY KEY (id)`
- `uq_error_type__code`: `UNIQUE (code)`
- `uq_error_type__name`: `UNIQUE (name)`

### core.policy_version

Version of the data processing policy that users consent to.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `version_number` | text | no | UQ | Version number, for example 1.2. |
| `effective_from` | date | no |  | Date from which the version is in force. |
| `policy_text` | text | no |  | Full text of the version, so that it is clear what exactly a user consented to. |

Constraints:

- `pk_policy_version`: `PRIMARY KEY (id)`
- `uq_policy_version__version_number`: `UNIQUE (version_number)`

### core.visual_style

Visual style of the interface. Some styles are available to everyone, others are unlocked as a reward for closed scales.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `code` | text | no | UQ | Stable identifier used by the application. Never changed or translated. |
| `name` | text | no | UQ | Style name shown to users. |
| `display_order` | integer | no | UQ | Position of the style in the list. |
| `unlock_closed_scale_count` | integer | yes |  | Number of scales, from 1 to 4, the learner must have closed to unlock the style. NULL for a style available to everyone. |

Constraints:

- `pk_visual_style`: `PRIMARY KEY (id)`
- `uq_visual_style__code`: `UNIQUE (code)`
- `uq_visual_style__display_order`: `UNIQUE (display_order)`
- `uq_visual_style__name`: `UNIQUE (name)`
- `ck_visual_style__unlock_scale_count_range`: `CHECK (((unlock_closed_scale_count >= 1) AND (unlock_closed_scale_count <= 4)))`

### core.pronunciation_variant

Pronunciation variant of a language, for example British and American English. Reference table.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `language_id` | bigint | no | FK → `core.language`, on delete RESTRICT | Language the variant belongs to. |
| `code` | text | no | UQ | Language and region code, for example en-GB. |
| `name` | text | no |  | Variant name. |

Constraints:

- `pk_pronunciation_variant`: `PRIMARY KEY (id)`
- `uq_pronunciation_variant__code`: `UNIQUE (code)`
- `uq_pronunciation_variant__id_and_language`: `UNIQUE (id, language_id)`
- `uq_pronunciation_variant__language_name`: `UNIQUE (language_id, name)`
- `fk_pronunciation_variant__language`: `FOREIGN KEY (language_id) REFERENCES core.language(id) ON DELETE RESTRICT`
- `ck_pronunciation_variant__code_format`: `CHECK ((code ~ '^[a-z]{2}-[A-Z]{2}$'::text))`

## Users and access

Accounts, consents, groups and the learning link: the pair of a learner and a teacher, or a learner and their own course. Almost everything a learner does hangs on a learning link.

### core.app_user

User account. One account can combine the roles of teacher, learner and self-directed learner.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `email` | text | no | UQ | Personal data. E-mail address, stored in lower case. A second registration with the same address is rejected. |
| `password_hash` | text | no |  | Password hash. The password itself is not stored. |
| `country_id` | bigint | no | FK → `core.country`, on delete RESTRICT | Country of the user. |
| `age_group` | text | no |  | Age group: 14-17 or adult. The date of birth is not stored. |
| `registration_role` | text | no |  | Role chosen at registration: teacher or learner. |
| `display_name` | text | yes |  | Personal data. Name shown to other users. NULL until the user sets it. |
| `interface_language_id` | bigint | no | FK → `core.language`, on delete RESTRICT | Language of the user interface. |
| `registered_at` | timestamp with time zone | no |  | Moment of registration. |
| `time_zone` | text | no |  | Full time zone name, for example Europe/Vilnius. Defines day boundaries for the queue and deadlines. |
| `daily_task_limit` | integer, default `30` | no |  | Maximum number of tasks in the daily queue. |
| `reminder_time` | time without time zone | yes |  | Time of day for the reminder e-mail, in the user time zone. NULL until the user chooses a time. |
| `reminders_enabled` | boolean, default `false` | no |  | Whether reminder e-mails are sent. Kept apart from the time so that switching off does not erase the chosen time. |
| `last_reminder_sent_at` | timestamp with time zone | yes |  | Moment the last reminder e-mail was sent. NULL until the first one. Used to send at most one e-mail a day. |
| `visual_style_id` | bigint | yes | FK → `core.visual_style`, on delete SET NULL | Visual style chosen by the user. NULL when the default style is used. |
| `show_added_glossaries` | boolean, default `true` | no |  | Whether glossaries added to the material are shown to the user. |

Constraints:

- `pk_app_user`: `PRIMARY KEY (id)`
- `uq_app_user__email`: `UNIQUE (email)`
- `fk_app_user__country`: `FOREIGN KEY (country_id) REFERENCES core.country(id) ON DELETE RESTRICT`
- `fk_app_user__interface_language`: `FOREIGN KEY (interface_language_id) REFERENCES core.language(id) ON DELETE RESTRICT`
- `fk_app_user__visual_style`: `FOREIGN KEY (visual_style_id) REFERENCES core.visual_style(id) ON DELETE SET NULL`
- `ck_app_user__age_group`: `CHECK ((age_group = ANY (ARRAY['14-17'::text, 'adult'::text])))`
- `ck_app_user__daily_task_limit_positive`: `CHECK ((daily_task_limit > 0))`
- `ck_app_user__email_lowercase`: `CHECK ((email = lower(email)))`
- `ck_app_user__registration_role`: `CHECK ((registration_role = ANY (ARRAY['teacher'::text, 'learner'::text])))`

### core.consent

Consent of a user, kept together with the policy version it was given under.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `app_user_id` | bigint | no | FK → `core.app_user`, on delete CASCADE | User who gave the consent. |
| `consent_kind` | text | no |  | Kind of consent: main or statistics. |
| `given_at` | timestamp with time zone | no |  | Moment the consent was given. |
| `policy_version_id` | bigint | no | FK → `core.policy_version`, on delete RESTRICT | Policy version the consent was given under. |
| `withdrawn_at` | timestamp with time zone | yes |  | Moment the consent was withdrawn. NULL while the consent is active. |

Constraints:

- `pk_consent`: `PRIMARY KEY (id)`
- `fk_consent__app_user`: `FOREIGN KEY (app_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE`
- `fk_consent__policy_version`: `FOREIGN KEY (policy_version_id) REFERENCES core.policy_version(id) ON DELETE RESTRICT`
- `ck_consent__consent_kind`: `CHECK ((consent_kind = ANY (ARRAY['main'::text, 'statistics'::text])))`
- `ck_consent__withdrawn_after_given`: `CHECK ((withdrawn_at >= given_at))`

Indexes besides those behind the constraints:

- `ix_consent__app_user`: `(app_user_id)`
- `uq_consent__active` (unique): `(app_user_id, consent_kind) WHERE (withdrawn_at IS NULL)`

### core.course

Own course of a self-directed learner.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `name` | text | no |  | Course name. |
| `owner_user_id` | bigint | no | FK → `core.app_user`, on delete CASCADE | User who owns the course. |
| `created_at` | timestamp with time zone | no |  | Moment of creation. |

Constraints:

- `pk_course`: `PRIMARY KEY (id)`
- `fk_course__owner_user`: `FOREIGN KEY (owner_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE`

Indexes besides those behind the constraints:

- `ix_course__owner_user`: `(owner_user_id)`

### core.study_group

Group of learners of one teacher. A group studies one language.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `name` | text | no |  | Group name. |
| `teacher_user_id` | bigint | no | FK → `core.app_user`, on delete CASCADE | Teacher who leads the group. |
| `created_at` | timestamp with time zone | no |  | Moment of creation. |
| `study_language_id` | bigint | no | FK → `core.language`, on delete RESTRICT | Language the group studies. |

Constraints:

- `pk_study_group`: `PRIMARY KEY (id)`
- `fk_study_group__study_language`: `FOREIGN KEY (study_language_id) REFERENCES core.language(id) ON DELETE RESTRICT`
- `fk_study_group__teacher_user`: `FOREIGN KEY (teacher_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE`

Indexes besides those behind the constraints:

- `ix_study_group__teacher_user`: `(teacher_user_id)`

### core.learning_link

Learning link: a learner with a teacher, or a learner with an own course. History, answers and level belong to the link, not to the person.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `link_kind` | text | no |  | Kind of link: with_teacher or self_directed. |
| `learner_user_id` | bigint | no | FK → `core.app_user`, on delete CASCADE | User who learns. |
| `teacher_user_id` | bigint | yes | FK → `core.app_user`, on delete SET NULL | Teacher. NULL for a self-directed link and after the teacher account is deleted. |
| `course_id` | bigint | yes | FK → `core.course`, on delete CASCADE; UQ | Own course. Filled for a self-directed link only. |
| `goal` | text | yes |  | Learning goal in the words of the user. NULL until set. |
| `target_cefr_level_id` | bigint | yes | FK → `core.cefr_level`, on delete RESTRICT | Target CEFR level. NULL until the goal is set. |
| `started_at` | timestamp with time zone | no |  | Moment the link started. |
| `ended_at` | timestamp with time zone | yes |  | Moment the link ended. NULL while the link is active. After it the teacher sees nothing further. |
| `study_language_id` | bigint | no | FK → `core.language`, on delete RESTRICT | Language studied within the link. |
| `level_decision_mode` | text | no |  | Who records a level change: self (the user decides) or system (the system is trusted). |
| `adaptation_decision_mode` | text | no |  | Who approves an adaptation proposal: self (the user decides) or system (the system is trusted). |
| `queue_decision_mode` | text | no |  | Who decides on the revision queue: self (the user decides) or system (the system is trusted). |
| `total_course_hours` | integer | yes |  | Total time budget of the course in hours. NULL until it is set. |
| `desired_end_date` | date | yes |  | Date by which the learner wants to finish. NULL until it is set. |
| `new_material_share` | numeric(3,2), default `0.10` | no |  | Share of new material in the daily queue, from 0 to 1. The learner can change it. |
| `failures_before_deferral` | integer, default `8` | no |  | Number of failed attempts after which a task is deferred instead of being repeated. |
| `access_until` | date | yes |  | Last day the learner may go on revising the exercises of a closed link with a teacher, at most 365 days after the end. NULL when no such access is left. |

Constraints:

- `pk_learning_link`: `PRIMARY KEY (id)`
- `uq_learning_link__course`: `UNIQUE (course_id)`
- `fk_learning_link__course`: `FOREIGN KEY (course_id) REFERENCES core.course(id) ON DELETE CASCADE`
- `fk_learning_link__learner_user`: `FOREIGN KEY (learner_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE`
- `fk_learning_link__study_language`: `FOREIGN KEY (study_language_id) REFERENCES core.language(id) ON DELETE RESTRICT`
- `fk_learning_link__target_cefr_level`: `FOREIGN KEY (target_cefr_level_id) REFERENCES core.cefr_level(id) ON DELETE RESTRICT`
- `fk_learning_link__teacher_user`: `FOREIGN KEY (teacher_user_id) REFERENCES core.app_user(id) ON DELETE SET NULL`
- `ck_learning_link__access_after_end`: `CHECK (((access_until IS NULL) OR ((link_kind = 'with_teacher'::text) AND (ended_at IS NOT NULL) AND (access_until >= ((ended_at AT TIME ZONE 'UTC'::text))::date) AND (access_until <= (((ended_at AT TIME ZONE 'UTC'::text))::date + 365)))))`
- `ck_learning_link__adaptation_decision_mode`: `CHECK ((adaptation_decision_mode = ANY (ARRAY['self'::text, 'system'::text])))`
- `ck_learning_link__ended_after_started`: `CHECK ((ended_at >= started_at))`
- `ck_learning_link__failures_before_deferral_positive`: `CHECK ((failures_before_deferral > 0))`
- `ck_learning_link__kind_consistency`: `CHECK ((((link_kind = 'self_directed'::text) AND (course_id IS NOT NULL) AND (teacher_user_id IS NULL)) OR ((link_kind = 'with_teacher'::text) AND (course_id IS NULL))))`
- `ck_learning_link__level_decision_mode`: `CHECK ((level_decision_mode = ANY (ARRAY['self'::text, 'system'::text])))`
- `ck_learning_link__link_kind`: `CHECK ((link_kind = ANY (ARRAY['with_teacher'::text, 'self_directed'::text])))`
- `ck_learning_link__new_material_share_range`: `CHECK (((new_material_share >= (0)::numeric) AND (new_material_share <= (1)::numeric)))`
- `ck_learning_link__queue_decision_mode`: `CHECK ((queue_decision_mode = ANY (ARRAY['self'::text, 'system'::text])))`
- `ck_learning_link__teacher_present`: `CHECK (((link_kind <> 'with_teacher'::text) OR (teacher_user_id IS NOT NULL) OR (ended_at IS NOT NULL)))`
- `ck_learning_link__total_course_hours_positive`: `CHECK ((total_course_hours > 0))`

Indexes besides those behind the constraints:

- `ix_learning_link__learner_user`: `(learner_user_id)`
- `ix_learning_link__teacher_user`: `(teacher_user_id)`
- `uq_learning_link__open_self_directed` (unique): `(learner_user_id, study_language_id) WHERE ((link_kind = 'self_directed'::text) AND (ended_at IS NULL))`
- `uq_learning_link__open_triple` (unique): `(learner_user_id, teacher_user_id, study_language_id) WHERE (ended_at IS NULL)`

### core.group_membership

Membership of a learning link in a group, with its history.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `learning_link_id` | bigint | no | FK → `core.learning_link`, on delete CASCADE | Learning link of the member. |
| `study_group_id` | bigint | no | FK → `core.study_group`, on delete CASCADE | Group. |
| `joined_at` | timestamp with time zone | no |  | Moment of joining. |
| `left_at` | timestamp with time zone | yes |  | Moment of leaving. NULL while a member. Results stay in the group archive afterwards. |

Constraints:

- `pk_group_membership`: `PRIMARY KEY (id)`
- `fk_group_membership__learning_link`: `FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE`
- `fk_group_membership__study_group`: `FOREIGN KEY (study_group_id) REFERENCES core.study_group(id) ON DELETE CASCADE`
- `ck_group_membership__left_after_joined`: `CHECK ((left_at >= joined_at))`

Indexes besides those behind the constraints:

- `ix_group_membership__learning_link`: `(learning_link_id)`
- `ix_group_membership__study_group`: `(study_group_id)`
- `uq_group_membership__active` (unique): `(learning_link_id, study_group_id) WHERE (left_at IS NULL)`

### core.invitation

Invitation to join a group by a link.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `study_group_id` | bigint | no | FK → `core.study_group`, on delete CASCADE | Group the invitation leads to. |
| `code` | text | no | UQ | Random value from which the link address is built. |
| `valid_until` | timestamp with time zone | no |  | Moment until which the invitation is valid. |
| `revoked_at` | timestamp with time zone | yes |  | Moment the invitation was revoked. NULL while not revoked. |

Constraints:

- `pk_invitation`: `PRIMARY KEY (id)`
- `uq_invitation__code`: `UNIQUE (code)`
- `fk_invitation__study_group`: `FOREIGN KEY (study_group_id) REFERENCES core.study_group(id) ON DELETE CASCADE`

Indexes besides those behind the constraints:

- `ix_invitation__study_group`: `(study_group_id)`

### core.erasure_request

Request of a user to erase personal data. The record outlives the erasure, without references to the person.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `app_user_id` | bigint | yes | FK → `core.app_user`, on delete SET NULL | User who made the request. Becomes NULL after the account is deleted. |
| `learning_link_id` | bigint | yes | FK → `core.learning_link`, on delete SET NULL | Learning link to erase. Becomes NULL after the erasure. |
| `requested_at` | timestamp with time zone | no |  | Moment of the request. |
| `confirm_by` | timestamp with time zone | no |  | Moment by which the request must be confirmed, otherwise it is cancelled. |
| `confirmed_at` | timestamp with time zone | yes |  | Moment of confirmation. NULL until confirmed. |
| `execute_by` | timestamp with time zone | yes |  | Moment before which the erasure is not carried out. NULL when no term is set. |
| `status` | text | no |  | State: awaiting_confirmation, confirmed, executed or cancelled. |
| `scope` | text | no |  | What is erased: single_link or everything. |
| `confirmation_code_hash` | text | yes |  | Hash of the confirmation code sent by e-mail. Cleared after confirmation or cancellation. |
| `material_retention_days` | integer | yes |  | For how many days the materials stay available to the learners after the account is erased, from 0 to 365. Chosen by the user; NULL means the default of 7 days. |

Constraints:

- `pk_erasure_request`: `PRIMARY KEY (id)`
- `fk_erasure_request__app_user`: `FOREIGN KEY (app_user_id) REFERENCES core.app_user(id) ON DELETE SET NULL`
- `fk_erasure_request__learning_link`: `FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE SET NULL`
- `ck_erasure_request__material_retention_days_range`: `CHECK (((material_retention_days >= 0) AND (material_retention_days <= 365)))`
- `ck_erasure_request__scope`: `CHECK ((scope = ANY (ARRAY['single_link'::text, 'everything'::text])))`
- `ck_erasure_request__status`: `CHECK ((status = ANY (ARRAY['awaiting_confirmation'::text, 'confirmed'::text, 'executed'::text, 'cancelled'::text])))`

Indexes besides those behind the constraints:

- `ix_erasure_request__app_user`: `(app_user_id)`
- `ix_erasure_request__learning_link`: `(learning_link_id)`

### core.export_request

Request of a user to export own data. The state of the request is derived from its dates.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `app_user_id` | bigint | no | FK → `core.app_user`, on delete CASCADE | User who requested the export. |
| `learning_link_id` | bigint | yes | FK → `core.learning_link`, on delete CASCADE | Learning link whose data is exported. NULL when all data of the user is exported. |
| `requested_at` | timestamp with time zone | no |  | Moment the export was requested. |
| `prepare_by` | timestamp with time zone | no |  | Deadline for preparing the export, no later than one month after the request. |
| `prepared_at` | timestamp with time zone | yes |  | Moment the export was prepared. NULL while it is being prepared. |
| `file_location` | text | yes |  | Address of the export file. NULL until the export is ready. |
| `available_until` | timestamp with time zone | yes |  | Moment until which the file can be downloaded. NULL until the export is ready. |

Constraints:

- `pk_export_request`: `PRIMARY KEY (id)`
- `fk_export_request__app_user`: `FOREIGN KEY (app_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE`
- `fk_export_request__learning_link`: `FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE`

Indexes besides those behind the constraints:

- `ix_export_request__app_user`: `(app_user_id)`
- `ix_export_request__learning_link`: `(learning_link_id)`

### core.summary_link

Read-only link by which a learner shares a summary of own progress.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `learning_link_id` | bigint | no | FK → `core.learning_link`, on delete CASCADE | Learning link whose summary is shared. |
| `code` | text | no | UQ | Random value used in the address of the link instead of the id. |
| `created_at` | timestamp with time zone | no |  | Moment the link was created. |
| `valid_until` | timestamp with time zone | no |  | Moment until which the link works. Set by the learner, 14 days from creation by default. |
| `revoked_at` | timestamp with time zone | yes |  | Moment the link was revoked. NULL while it is in force. |

Constraints:

- `pk_summary_link`: `PRIMARY KEY (id)`
- `uq_summary_link__code`: `UNIQUE (code)`
- `fk_summary_link__learning_link`: `FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE`

Indexes besides those behind the constraints:

- `ix_summary_link__learning_link`: `(learning_link_id)`

### core.feature_toggle

Feature switched on or off by a teacher for a group or for one learner. A row exists only where the teacher changed the default; the setting of a learner overrides the setting of the group.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `feature` | text | no |  | Feature: adaptation, harder_variants or oral_error_entry. |
| `study_group_id` | bigint | yes | FK → `core.study_group`, on delete CASCADE | Group the setting applies to. Exactly one of study_group_id and learning_link_id is filled. |
| `learning_link_id` | bigint | yes | FK → `core.learning_link`, on delete CASCADE | Learning link the setting applies to: a setting for one learner. |
| `is_enabled` | boolean | no |  | True when the feature is switched on. |
| `changed_at` | timestamp with time zone | no |  | Moment the setting was last changed. |

Constraints:

- `pk_feature_toggle`: `PRIMARY KEY (id)`
- `uq_feature_toggle__group_feature`: `UNIQUE (study_group_id, feature)`
- `uq_feature_toggle__link_feature`: `UNIQUE (learning_link_id, feature)`
- `fk_feature_toggle__learning_link`: `FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE`
- `fk_feature_toggle__study_group`: `FOREIGN KEY (study_group_id) REFERENCES core.study_group(id) ON DELETE CASCADE`
- `ck_feature_toggle__feature`: `CHECK ((feature = ANY (ARRAY['adaptation'::text, 'harder_variants'::text, 'oral_error_entry'::text])))`
- `ck_feature_toggle__one_target`: `CHECK ((num_nonnulls(study_group_id, learning_link_id) = 1))`

### core.shown_tooltip

Onboarding tooltip already shown to a user, so that it is not shown again.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `app_user_id` | bigint | no | PK; FK → `core.app_user`, on delete CASCADE | User who saw the tooltip. |
| `interface_element` | text | no | PK | Identifier of the interface element. The list of elements is kept in the application code. |
| `shown_at` | timestamp with time zone | no |  | Moment the tooltip was shown. |

Constraints:

- `pk_shown_tooltip`: `PRIMARY KEY (app_user_id, interface_element)`
- `fk_shown_tooltip__app_user`: `FOREIGN KEY (app_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE`

### core.pronunciation_choice

Pronunciation variant chosen by a learner for a language. Belongs to the learner, not to a learning link: the choice is the same with every teacher.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `learner_user_id` | bigint | no | FK → `core.app_user`, on delete CASCADE | Learner who made the choice. |
| `language_id` | bigint | no | FK part → `core.pronunciation_variant` | Language the choice is made for. Repeats the language of the variant so that one choice per language can be enforced. |
| `pronunciation_variant_id` | bigint | no | FK part → `core.pronunciation_variant` | Chosen variant. |

Constraints:

- `pk_pronunciation_choice`: `PRIMARY KEY (id)`
- `uq_pronunciation_choice__learner_language`: `UNIQUE (learner_user_id, language_id)`
- `fk_pronunciation_choice__learner_user`: `FOREIGN KEY (learner_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE`
- `fk_pronunciation_choice__variant`: `FOREIGN KEY (pronunciation_variant_id, language_id) REFERENCES core.pronunciation_variant(id, language_id) ON DELETE RESTRICT`

### core.learning_link_pseudonym

Correspondence between a learning link and the random code used in statistics. The only key from statistics back to a person; deleted with the link or when the statistics consent is withdrawn.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `learning_link_id` | bigint | no | FK → `core.learning_link`, on delete CASCADE; UQ | Learning link. One code per link. |
| `random_code` | uuid, default `gen_random_uuid()` | no | UQ | Random code generated by the database. |
| `created_at` | timestamp with time zone | no |  | Moment the code was created. |

Constraints:

- `pk_learning_link_pseudonym`: `PRIMARY KEY (id)`
- `uq_learning_link_pseudonym__code`: `UNIQUE (random_code)`
- `uq_learning_link_pseudonym__link`: `UNIQUE (learning_link_id)`
- `fk_learning_link_pseudonym__learning_link`: `FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE`

## Materials and parsing

Uploaded PDF materials and what parsing produced from them: exercises, their tasks, flags on doubtful places, images and words.

### core.folder

Folder of the material library. A folder of kind book holds the parts of one large document.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `owner_user_id` | bigint | no | FK → `core.app_user`, on delete CASCADE | User who owns the folder. |
| `name` | text | no |  | Folder name. |
| `parent_folder_id` | bigint | yes | FK → `core.folder`, on delete RESTRICT | Folder that contains this one. NULL for a top-level folder. |
| `folder_kind` | text | no |  | Kind: ordinary or book. |
| `split_method` | text | yes |  | How the document was split into parts: by_contents, by_headings or by_equal_ranges. Filled only for a book, NULL for an ordinary folder. |

Constraints:

- `pk_folder`: `PRIMARY KEY (id)`
- `fk_folder__owner_user`: `FOREIGN KEY (owner_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE`
- `fk_folder__parent_folder`: `FOREIGN KEY (parent_folder_id) REFERENCES core.folder(id) ON DELETE RESTRICT`
- `ck_folder__folder_kind`: `CHECK ((folder_kind = ANY (ARRAY['ordinary'::text, 'book'::text])))`
- `ck_folder__split_method`: `CHECK ((split_method = ANY (ARRAY['by_contents'::text, 'by_headings'::text, 'by_equal_ranges'::text])))`
- `ck_folder__split_only_for_book`: `CHECK (((split_method IS NULL) OR (folder_kind = 'book'::text)))`

Indexes besides those behind the constraints:

- `ix_folder__owner_user`: `(owner_user_id)`
- `ix_folder__parent_folder`: `(parent_folder_id)`

### core.material

Uploaded PDF learning material. The file itself is stored outside the database.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `owner_user_id` | bigint | yes | FK → `core.app_user`, on delete CASCADE | Owner of the material. NULL when the owner erased the account and the material is kept for the learners until retained_until. |
| `name` | text | no |  | Material name. Used for search in the library. |
| `file_location` | text | no |  | Address of the file. |
| `file_size_bytes` | integer | no |  | File size in bytes. The size limit is an application setting, not a database rule. |
| `page_count` | integer | no |  | Number of pages. The page limit is an application setting. |
| `has_text_layer` | boolean | no |  | True when the PDF has a text layer. |
| `cefr_level_id` | bigint | yes | FK → `core.cefr_level`, on delete RESTRICT | Level of the material, set by the uploader. NULL until set. |
| `study_language_id` | bigint | no | FK → `core.language`, on delete RESTRICT | Language the material teaches. Dictionaries and audio depend on it. |
| `processing_status` | text | no |  | Processing status: processing, parsed, text_not_extracted or not_parsed. |
| `uploaded_at` | timestamp with time zone | no |  | Moment of upload. |
| `course_id` | bigint | yes | FK → `core.course`, on delete SET NULL | Own course the material belongs to. NULL for a material of a teacher. |
| `folder_id` | bigint | yes | FK → `core.folder`, on delete RESTRICT | Folder the material lies in. NULL when it lies outside folders. |
| `part_number` | integer | yes |  | Number of the part inside a book. NULL for an ordinary material. |
| `source_page_from` | integer | yes |  | First page of the part in the source document. NULL for an ordinary material. |
| `source_page_to` | integer | yes |  | Last page of the part in the source document. NULL for an ordinary material. |
| `archived_at` | timestamp with time zone | yes |  | Moment the material was moved to the archive. NULL while it is in the library. |
| `retained_until` | date | yes |  | Last day the material of an erased owner is kept for the learners who worked with it. NULL for a material with an owner. |

Constraints:

- `pk_material`: `PRIMARY KEY (id)`
- `fk_material__cefr_level`: `FOREIGN KEY (cefr_level_id) REFERENCES core.cefr_level(id) ON DELETE RESTRICT`
- `fk_material__course`: `FOREIGN KEY (course_id) REFERENCES core.course(id) ON DELETE SET NULL`
- `fk_material__folder`: `FOREIGN KEY (folder_id) REFERENCES core.folder(id) ON DELETE RESTRICT`
- `fk_material__owner_user`: `FOREIGN KEY (owner_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE`
- `fk_material__study_language`: `FOREIGN KEY (study_language_id) REFERENCES core.language(id) ON DELETE RESTRICT`
- `ck_material__file_size_positive`: `CHECK ((file_size_bytes > 0))`
- `ck_material__ownerless_is_retained`: `CHECK (((owner_user_id IS NULL) = (retained_until IS NOT NULL)))`
- `ck_material__page_count_positive`: `CHECK ((page_count > 0))`
- `ck_material__part_number_positive`: `CHECK ((part_number > 0))`
- `ck_material__processing_status`: `CHECK ((processing_status = ANY (ARRAY['processing'::text, 'parsed'::text, 'text_not_extracted'::text, 'not_parsed'::text])))`
- `ck_material__source_pages`: `CHECK ((((source_page_from IS NULL) AND (source_page_to IS NULL)) OR ((source_page_from IS NOT NULL) AND (source_page_to IS NOT NULL) AND (source_page_from <= source_page_to))))`

Indexes besides those behind the constraints:

- `ix_material__course`: `(course_id)`
- `ix_material__folder`: `(folder_id)`
- `ix_material__owner_user`: `(owner_user_id)`
- `ix_material__retained_until`: `(retained_until) WHERE (retained_until IS NOT NULL)`
- `uq_material__folder_part` (unique): `(folder_id, part_number) WHERE (part_number IS NOT NULL)`

### core.parsing_run

One run of parsing a material into exercises.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `material_id` | bigint | no | FK → `core.material`, on delete CASCADE | Material that was parsed. |
| `started_at` | timestamp with time zone | no |  | Moment the run started. |
| `finished_at` | timestamp with time zone | yes |  | Moment the run finished. NULL while running. Distinguishes a running parse from a stalled one. |
| `outcome` | text | yes |  | Outcome: completed, timed_out or text_not_extracted. NULL while running. |

Constraints:

- `pk_parsing_run`: `PRIMARY KEY (id)`
- `fk_parsing_run__material`: `FOREIGN KEY (material_id) REFERENCES core.material(id) ON DELETE CASCADE`
- `ck_parsing_run__finished_after_started`: `CHECK ((finished_at >= started_at))`
- `ck_parsing_run__outcome`: `CHECK ((outcome = ANY (ARRAY['completed'::text, 'timed_out'::text, 'text_not_extracted'::text])))`

Indexes besides those behind the constraints:

- `ix_parsing_run__material`: `(material_id)`

### core.topic

Topic of exercises: from the common catalogue or created by a user.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `name` | text | no |  | Topic name. Unique for one owner and separately within the common catalogue. |
| `owner_user_id` | bigint | yes | FK → `core.app_user`, on delete CASCADE | User who created the topic. NULL for topics of the common catalogue. |

Constraints:

- `pk_topic`: `PRIMARY KEY (id)`
- `uq_topic__owner_name`: `UNIQUE (owner_user_id, name)`
- `fk_topic__owner_user`: `FOREIGN KEY (owner_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE`

Indexes besides those behind the constraints:

- `uq_topic__catalogue_name` (unique): `(name) WHERE (owner_user_id IS NULL)`

### core.exercise

Exercise extracted from a material. Consists of tasks.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `parsing_run_id` | bigint | no | FK → `core.parsing_run`, on delete CASCADE | Parsing run that produced the exercise. Through it the exercise knows its material. |
| `exercise_type_id` | bigint | yes | FK → `core.exercise_type`, on delete RESTRICT | Exercise type. NULL when the type was not recognised. |
| `topic_id` | bigint | yes | FK → `core.topic`, on delete RESTRICT | Topic. NULL until assigned. |
| `status` | text | no |  | Status: draft or approved. |
| `number_in_document` | text | yes |  | Number of the exercise in the document, for example 3a. Other exercises refer to it. NULL when the document gives no number. |
| `instruction_text` | text | no |  | Instruction common to all tasks of the exercise. |
| `shared_body` | jsonb | yes |  | Part of the body shared by the tasks, such as a word bank. NULL when there is none. Structure is described in the type catalogue. |
| `source_page` | integer | no |  | Page of the document where the exercise is. |
| `excluded_at` | timestamp with time zone | yes |  | Moment the exercise was excluded. NULL while not excluded. Cleared on return; the status stays as it was. |
| `scale_id` | bigint | yes | FK → `core.scale`, on delete RESTRICT | Scale the exercise trains. Must be filled before approval. |
| `source_exercise_id` | bigint | yes | FK → `core.exercise`, on delete SET NULL | Exercise this one was converted from. NULL for an exercise that was not converted. |
| `archived_at` | timestamp with time zone | yes |  | Moment the exercise was moved to the archive. NULL while it is in the library. |
| `is_typo_tolerated` | boolean, default `false` | no |  | Whether a typed answer with a typo is accepted. Set by the author of the material. |

Constraints:

- `pk_exercise`: `PRIMARY KEY (id)`
- `fk_exercise__exercise_type`: `FOREIGN KEY (exercise_type_id) REFERENCES core.exercise_type(id) ON DELETE RESTRICT`
- `fk_exercise__parsing_run`: `FOREIGN KEY (parsing_run_id) REFERENCES core.parsing_run(id) ON DELETE CASCADE`
- `fk_exercise__scale`: `FOREIGN KEY (scale_id) REFERENCES core.scale(id) ON DELETE RESTRICT`
- `fk_exercise__source_exercise`: `FOREIGN KEY (source_exercise_id) REFERENCES core.exercise(id) ON DELETE SET NULL`
- `fk_exercise__topic`: `FOREIGN KEY (topic_id) REFERENCES core.topic(id) ON DELETE RESTRICT`
- `ck_exercise__approved_has_scale`: `CHECK (((status <> 'approved'::text) OR (scale_id IS NOT NULL)))`
- `ck_exercise__source_page_positive`: `CHECK ((source_page > 0))`
- `ck_exercise__status`: `CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text])))`

Indexes besides those behind the constraints:

- `ix_exercise__parsing_run`: `(parsing_run_id)`
- `ix_exercise__source_exercise`: `(source_exercise_id)`
- `ix_exercise__topic`: `(topic_id)`

### core.task

Single task of an exercise: the unit a learner answers.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `exercise_id` | bigint | no | FK → `core.exercise`, on delete CASCADE | Exercise the task belongs to. |
| `number_in_exercise` | integer | no |  | Number of the task inside the exercise. The answer key is matched to the task by it. |
| `task_text` | text | no |  | Task text, character for character as in the document. |
| `body` | jsonb | no |  | Task body: gaps, options, key answers, example flag, highlighted parts. Structure is described in the type catalogue. |
| `source_page` | integer | no |  | Page of the document where the task is. |
| `position_on_page` | integer | no |  | Ordinal position of the task on the page, from top to bottom. |
| `text_audio_location` | text | yes |  | Address of the audio file with the task text. NULL until the audio is requested. |

Constraints:

- `pk_task`: `PRIMARY KEY (id)`
- `uq_task__exercise_number`: `UNIQUE (exercise_id, number_in_exercise)`
- `fk_task__exercise`: `FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE`
- `ck_task__number_positive`: `CHECK ((number_in_exercise > 0))`
- `ck_task__position_positive`: `CHECK ((position_on_page > 0))`
- `ck_task__source_page_positive`: `CHECK ((source_page > 0))`

### core.exercise_dependency

Dependency between exercises: one exercise relies on another.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `dependent_exercise_id` | bigint | no | FK → `core.exercise`, on delete CASCADE | Exercise that depends on another one. |
| `prerequisite_exercise_id` | bigint | no | FK → `core.exercise`, on delete CASCADE | Exercise it depends on. |

Constraints:

- `pk_exercise_dependency`: `PRIMARY KEY (id)`
- `uq_exercise_dependency__pair`: `UNIQUE (dependent_exercise_id, prerequisite_exercise_id)`
- `fk_exercise_dependency__dependent_exercise`: `FOREIGN KEY (dependent_exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE`
- `fk_exercise_dependency__prerequisite_exercise`: `FOREIGN KEY (prerequisite_exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE`
- `ck_exercise_dependency__different_exercises`: `CHECK ((dependent_exercise_id <> prerequisite_exercise_id))`

Indexes besides those behind the constraints:

- `ix_exercise_dependency__prerequisite_exercise`: `(prerequisite_exercise_id)`

### core.flag

Flag on a doubtful place of parsed material that the author must confirm or correct.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `task_id` | bigint | yes | FK → `core.task`, on delete CASCADE | Flagged task. Exactly one of task_id and exercise_id is filled. |
| `exercise_id` | bigint | yes | FK → `core.exercise`, on delete CASCADE | Flagged exercise. Exactly one of task_id and exercise_id is filled. |
| `place_in_task` | text | yes |  | Flagged part of the task body: which gap or answer. NULL when the whole task is flagged. |
| `flag_reason_id` | bigint | no | FK → `core.flag_reason`, on delete RESTRICT | Reason of the flag. |
| `status` | text | no |  | State: pending, confirmed or corrected. |
| `original_value` | text | yes |  | Value that stood in the document before the author corrected it. NULL until a correction is made. |
| `placed_by_user_id` | bigint | yes | FK → `core.app_user`, on delete SET NULL | User who placed the flag. NULL when the system placed it during parsing. |
| `placed_at` | timestamp with time zone | no |  | Moment the flag was placed. |
| `closed_at` | timestamp with time zone | yes |  | Moment the flag was closed. NULL while it is pending. |

Constraints:

- `pk_flag`: `PRIMARY KEY (id)`
- `fk_flag__exercise`: `FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE`
- `fk_flag__flag_reason`: `FOREIGN KEY (flag_reason_id) REFERENCES core.flag_reason(id) ON DELETE RESTRICT`
- `fk_flag__placed_by_user`: `FOREIGN KEY (placed_by_user_id) REFERENCES core.app_user(id) ON DELETE SET NULL`
- `fk_flag__task`: `FOREIGN KEY (task_id) REFERENCES core.task(id) ON DELETE CASCADE`
- `ck_flag__one_target`: `CHECK ((num_nonnulls(task_id, exercise_id) = 1))`
- `ck_flag__status`: `CHECK ((status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'corrected'::text])))`

Indexes besides those behind the constraints:

- `ix_flag__exercise`: `(exercise_id)`
- `ix_flag__placed_by_user`: `(placed_by_user_id)`
- `ix_flag__task`: `(task_id)`

### core.image

Image that belongs to a task or to a whole exercise. The file itself is stored outside the database.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `task_id` | bigint | yes | FK → `core.task`, on delete CASCADE | Task the image belongs to. Exactly one of task_id and exercise_id is filled. |
| `exercise_id` | bigint | yes | FK → `core.exercise`, on delete CASCADE | Exercise the image belongs to. Exactly one of task_id and exercise_id is filled. |
| `file_location` | text | no |  | Address of the file. |
| `origin` | text | no |  | Origin: source (taken from the document) or redrawn. |
| `source_page` | integer | no |  | Page of the document where the image is. |
| `image_kind` | text | no |  | Kind: ordinary, grid or diagram. Redrawing is not offered for a grid or a diagram. |
| `source_image_id` | bigint | yes | FK → `core.image`, on delete CASCADE | Image this one was redrawn from. Filled only for a redrawn image. |
| `confirmed_at` | timestamp with time zone | yes |  | Moment the author confirmed the redrawn image. NULL while it waits for the decision; always NULL for a source image. |

Constraints:

- `pk_image`: `PRIMARY KEY (id)`
- `fk_image__exercise`: `FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE`
- `fk_image__source_image`: `FOREIGN KEY (source_image_id) REFERENCES core.image(id) ON DELETE CASCADE`
- `fk_image__task`: `FOREIGN KEY (task_id) REFERENCES core.task(id) ON DELETE CASCADE`
- `ck_image__image_kind`: `CHECK ((image_kind = ANY (ARRAY['ordinary'::text, 'grid'::text, 'diagram'::text])))`
- `ck_image__one_target`: `CHECK ((num_nonnulls(task_id, exercise_id) = 1))`
- `ck_image__origin`: `CHECK ((origin = ANY (ARRAY['source'::text, 'redrawn'::text])))`
- `ck_image__origin_matches_source`: `CHECK ((((origin = 'redrawn'::text) AND (source_image_id IS NOT NULL)) OR ((origin = 'source'::text) AND (source_image_id IS NULL))))`
- `ck_image__source_page_positive`: `CHECK ((source_page > 0))`

Indexes besides those behind the constraints:

- `ix_image__exercise`: `(exercise_id)`
- `ix_image__source_image`: `(source_image_id)`
- `ix_image__task`: `(task_id)`

### core.presentation_item

Presentation element added to an exercise or a task on request: illustration, hint or glossary. It never changes the content of tasks and keys.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `exercise_id` | bigint | yes | FK → `core.exercise`, on delete CASCADE | Exercise the element belongs to. Exactly one of exercise_id and task_id is filled. |
| `task_id` | bigint | yes | FK → `core.task`, on delete CASCADE | Task the element belongs to. Exactly one of exercise_id and task_id is filled. |
| `item_kind` | text | no |  | Kind: illustration, hint or glossary. |
| `content` | text | yes |  | Text of the hint or glossary. NULL for an illustration. |
| `file_location` | text | yes |  | Address of the file. Filled only for an illustration. |
| `generated_at` | timestamp with time zone | no |  | Moment the element was generated. |
| `confirmed_at` | timestamp with time zone | yes |  | Moment the author confirmed the element. NULL while it is pending; until then it is not shown to learners. |

Constraints:

- `pk_presentation_item`: `PRIMARY KEY (id)`
- `fk_presentation_item__exercise`: `FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE`
- `fk_presentation_item__task`: `FOREIGN KEY (task_id) REFERENCES core.task(id) ON DELETE CASCADE`
- `ck_presentation_item__content_matches_kind`: `CHECK ((((item_kind = 'illustration'::text) AND (file_location IS NOT NULL) AND (content IS NULL)) OR ((item_kind = ANY (ARRAY['hint'::text, 'glossary'::text])) AND (content IS NOT NULL) AND (file_location IS NULL))))`
- `ck_presentation_item__item_kind`: `CHECK ((item_kind = ANY (ARRAY['illustration'::text, 'hint'::text, 'glossary'::text])))`
- `ck_presentation_item__one_target`: `CHECK ((num_nonnulls(exercise_id, task_id) = 1))`

Indexes besides those behind the constraints:

- `ix_presentation_item__exercise`: `(exercise_id)`
- `ix_presentation_item__task`: `(task_id)`

### core.word

Word with reference data obtained from external dictionaries and speech synthesis. A result is stored so that a paid service is not asked twice.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `language_id` | bigint | no | FK → `core.language`, on delete RESTRICT | Language of the word. |
| `spelling` | text | no |  | Spelling of the word. |
| `explanation` | text | yes |  | Explanation from a dictionary. NULL when the dictionary has no exact match. |
| `reference_requested_at` | timestamp with time zone | yes |  | Moment the reference data was requested. NULL when it was never requested. A date with empty reference data means the word was not found. |

Constraints:

- `pk_word`: `PRIMARY KEY (id)`
- `uq_word__id_and_language`: `UNIQUE (id, language_id)`
- `uq_word__language_spelling`: `UNIQUE (language_id, spelling)`
- `fk_word__language`: `FOREIGN KEY (language_id) REFERENCES core.language(id) ON DELETE RESTRICT`

### core.word_pronunciation

Transcription and audio of a word in one pronunciation variant.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `word_id` | bigint | no | FK part → `core.word` | Word. |
| `language_id` | bigint | no | FK part → `core.pronunciation_variant`; FK part → `core.word` | Language of the word and of the variant. Repeats both so that they cannot differ. |
| `pronunciation_variant_id` | bigint | no | FK part → `core.pronunciation_variant` | Pronunciation variant. |
| `transcription` | text | yes |  | Transcription from a dictionary. NULL when the dictionary has no exact match. |
| `audio_location` | text | yes |  | Address of the audio file. NULL until the audio exists. |
| `audio_requested_at` | timestamp with time zone | yes |  | Moment the audio was requested. NULL when it was never requested. |

Constraints:

- `pk_word_pronunciation`: `PRIMARY KEY (id)`
- `uq_word_pronunciation__word_variant`: `UNIQUE (word_id, pronunciation_variant_id)`
- `fk_word_pronunciation__variant`: `FOREIGN KEY (pronunciation_variant_id, language_id) REFERENCES core.pronunciation_variant(id, language_id) ON DELETE RESTRICT`
- `fk_word_pronunciation__word`: `FOREIGN KEY (word_id, language_id) REFERENCES core.word(id, language_id) ON DELETE CASCADE`

### core.task_target_word

Target word of a single task. Words of a shared word bank are stored in exercise_target_word.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `task_id` | bigint | no | PK; FK → `core.task`, on delete CASCADE | Task. |
| `word_id` | bigint | no | PK; FK → `core.word`, on delete RESTRICT | Target word. |

Constraints:

- `pk_task_target_word`: `PRIMARY KEY (task_id, word_id)`
- `fk_task_target_word__task`: `FOREIGN KEY (task_id) REFERENCES core.task(id) ON DELETE CASCADE`
- `fk_task_target_word__word`: `FOREIGN KEY (word_id) REFERENCES core.word(id) ON DELETE RESTRICT`

Indexes besides those behind the constraints:

- `ix_task_target_word__word`: `(word_id)`

### core.exercise_target_word

Target word of the shared word bank of an exercise, stored once for the whole exercise.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `exercise_id` | bigint | no | PK; FK → `core.exercise`, on delete CASCADE | Exercise. |
| `word_id` | bigint | no | PK; FK → `core.word`, on delete RESTRICT | Target word. |

Constraints:

- `pk_exercise_target_word`: `PRIMARY KEY (exercise_id, word_id)`
- `fk_exercise_target_word__exercise`: `FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE`
- `fk_exercise_target_word__word`: `FOREIGN KEY (word_id) REFERENCES core.word(id) ON DELETE RESTRICT`

Indexes besides those behind the constraints:

- `ix_exercise_target_word__word`: `(word_id)`

## Lessons and homework

What a teacher shows in a lesson and assigns as homework.

### core.lesson

Lesson held by a teacher: with a group or with one learner.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `study_group_id` | bigint | yes | FK → `core.study_group`, on delete CASCADE | Group, for a group lesson. Exactly one of study_group_id and learning_link_id is filled. |
| `learning_link_id` | bigint | yes | FK → `core.learning_link`, on delete CASCADE | Learning link, for an individual lesson. Exactly one of study_group_id and learning_link_id is filled. |
| `started_at` | timestamp with time zone | no |  | Moment the lesson started. |
| `ended_at` | timestamp with time zone | yes |  | Moment the lesson ended. NULL while the lesson is in progress. |

Constraints:

- `pk_lesson`: `PRIMARY KEY (id)`
- `fk_lesson__learning_link`: `FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE`
- `fk_lesson__study_group`: `FOREIGN KEY (study_group_id) REFERENCES core.study_group(id) ON DELETE CASCADE`
- `ck_lesson__ended_after_started`: `CHECK ((ended_at >= started_at))`
- `ck_lesson__one_target`: `CHECK ((num_nonnulls(study_group_id, learning_link_id) = 1))`

Indexes besides those behind the constraints:

- `ix_lesson__learning_link`: `(learning_link_id)`
- `ix_lesson__study_group`: `(study_group_id)`

### core.lesson_exercise

Exercise opened by the teacher during a lesson.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `lesson_id` | bigint | no | FK → `core.lesson`, on delete CASCADE | Lesson. |
| `exercise_id` | bigint | no | FK → `core.exercise`, on delete CASCADE | Exercise that was opened. |
| `shown_to_learning_link_id` | bigint | yes | FK → `core.learning_link`, on delete CASCADE | Learning link of the learner the exercise was shown to. NULL when shown to everyone. |
| `opened_at` | timestamp with time zone | no |  | Moment the exercise was opened. |

Constraints:

- `pk_lesson_exercise`: `PRIMARY KEY (id)`
- `fk_lesson_exercise__exercise`: `FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE`
- `fk_lesson_exercise__lesson`: `FOREIGN KEY (lesson_id) REFERENCES core.lesson(id) ON DELETE CASCADE`
- `fk_lesson_exercise__shown_to_learning_link`: `FOREIGN KEY (shown_to_learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE`

Indexes besides those behind the constraints:

- `ix_lesson_exercise__exercise`: `(exercise_id)`
- `ix_lesson_exercise__lesson`: `(lesson_id)`
- `ix_lesson_exercise__shown_to_learning_link`: `(shown_to_learning_link_id)`

### core.homework

Homework assigned by a teacher to a group or to one learner.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `assigned_by_user_id` | bigint | no | FK → `core.app_user`, on delete CASCADE | Teacher who assigned the homework. |
| `study_group_id` | bigint | yes | FK → `core.study_group`, on delete CASCADE | Group the homework is assigned to. NULL when assigned to one learner. |
| `due_at` | timestamp with time zone | no |  | Deadline, as a moment in time. |
| `assigned_at` | timestamp with time zone | no |  | Moment of assignment. |
| `adaptation_proposal_id` | bigint | yes | FK → `core.adaptation_proposal`, on delete SET NULL | Adaptation proposal the homework was created from. NULL when assigned manually. |

Constraints:

- `pk_homework`: `PRIMARY KEY (id)`
- `fk_homework__adaptation_proposal`: `FOREIGN KEY (adaptation_proposal_id) REFERENCES core.adaptation_proposal(id) ON DELETE SET NULL`
- `fk_homework__assigned_by_user`: `FOREIGN KEY (assigned_by_user_id) REFERENCES core.app_user(id) ON DELETE CASCADE`
- `fk_homework__study_group`: `FOREIGN KEY (study_group_id) REFERENCES core.study_group(id) ON DELETE CASCADE`
- `ck_homework__due_after_assigned`: `CHECK ((due_at >= assigned_at))`

Indexes besides those behind the constraints:

- `ix_homework__adaptation_proposal`: `(adaptation_proposal_id)`
- `ix_homework__assigned_by_user`: `(assigned_by_user_id)`
- `ix_homework__study_group`: `(study_group_id)`

### core.homework_assignment

Homework as received by one learner.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `homework_id` | bigint | no | FK → `core.homework`, on delete CASCADE | Homework. |
| `learning_link_id` | bigint | no | FK → `core.learning_link`, on delete CASCADE | Learning link of the learner who received it. |
| `personal_note` | text | yes |  | Note visible to this learner only. NULL when there is none. |
| `completed_at` | timestamp with time zone | yes |  | Moment of completion. NULL until completed. Completion is counted by the main items; additional items do not affect it. |

Constraints:

- `pk_homework_assignment`: `PRIMARY KEY (id)`
- `uq_homework_assignment__pair`: `UNIQUE (homework_id, learning_link_id)`
- `fk_homework_assignment__homework`: `FOREIGN KEY (homework_id) REFERENCES core.homework(id) ON DELETE CASCADE`
- `fk_homework_assignment__learning_link`: `FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE`

Indexes besides those behind the constraints:

- `ix_homework_assignment__learning_link`: `(learning_link_id)`

### core.homework_exercise

Whole exercise included in a homework.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `homework_id` | bigint | no | PK; FK → `core.homework`, on delete CASCADE | Homework. |
| `exercise_id` | bigint | no | PK; FK → `core.exercise`, on delete CASCADE | Exercise included in it. |
| `sort_order` | integer | no |  | Position of the exercise in the homework. |
| `item_kind` | text, default `'main'::text` | no |  | Kind: main or additional. Additional items are harder and optional. |

Constraints:

- `pk_homework_exercise`: `PRIMARY KEY (homework_id, exercise_id)`
- `uq_homework_exercise__order`: `UNIQUE (homework_id, sort_order)`
- `fk_homework_exercise__exercise`: `FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE`
- `fk_homework_exercise__homework`: `FOREIGN KEY (homework_id) REFERENCES core.homework(id) ON DELETE CASCADE`
- `ck_homework_exercise__item_kind`: `CHECK ((item_kind = ANY (ARRAY['main'::text, 'additional'::text])))`
- `ck_homework_exercise__sort_order_positive`: `CHECK ((sort_order > 0))`

Indexes besides those behind the constraints:

- `ix_homework_exercise__exercise`: `(exercise_id)`

### core.homework_task

Separate task included in a homework.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `homework_id` | bigint | no | PK; FK → `core.homework`, on delete CASCADE | Homework. |
| `task_id` | bigint | no | PK; FK → `core.task`, on delete CASCADE | Task included in it. |
| `sort_order` | integer | no |  | Position of the task in the homework. |
| `item_kind` | text, default `'main'::text` | no |  | Kind: main or additional. Additional items are harder and optional. |

Constraints:

- `pk_homework_task`: `PRIMARY KEY (homework_id, task_id)`
- `uq_homework_task__order`: `UNIQUE (homework_id, sort_order)`
- `fk_homework_task__homework`: `FOREIGN KEY (homework_id) REFERENCES core.homework(id) ON DELETE CASCADE`
- `fk_homework_task__task`: `FOREIGN KEY (task_id) REFERENCES core.task(id) ON DELETE CASCADE`
- `ck_homework_task__item_kind`: `CHECK ((item_kind = ANY (ARRAY['main'::text, 'additional'::text])))`
- `ck_homework_task__sort_order_positive`: `CHECK ((sort_order > 0))`

Indexes besides those behind the constraints:

- `ix_homework_task__task`: `(task_id)`

## Practice and revision

Answers of learners and the state of spaced repetition.

### core.answer

Answer of a learner to a task. One task can be answered many times: in a lesson, in homework, at each revision.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `task_id` | bigint | no | FK → `core.task`, on delete CASCADE | Task that was answered. |
| `learning_link_id` | bigint | no | FK → `core.learning_link`, on delete CASCADE | Learning link of the learner. |
| `homework_assignment_id` | bigint | yes | FK → `core.homework_assignment`, on delete SET NULL | Homework the answer was given for. NULL when not given for homework. |
| `content` | jsonb | no |  | Content of the answer. Its structure is defined by the exercise type. |
| `result` | text | no |  | Result: correct, incorrect or awaiting_review (to be checked by a person). |
| `attempt_number` | integer | no |  | Number of the attempt within one pass through the task. |
| `response_time_ms` | integer | no |  | Response time in milliseconds. |
| `active_time_ms` | integer | no |  | Active time in milliseconds: response time without long pauses. |
| `answered_at` | timestamp with time zone | no |  | Moment the answer was given. |
| `answer_change_count` | integer, default `0` | no |  | How many times the learner changed the answer before sending it. |
| `answer_rating` | text | yes |  | Rating derived by the system: error, slow_and_changed, moderate or fast. NULL while the answer awaits review. |
| `lesson_exercise_id` | bigint | yes | FK → `core.lesson_exercise`, on delete SET NULL | Showing of the exercise in a lesson during which the answer was given. NULL when not given in a lesson. |
| `error_type_id` | bigint | yes | FK → `core.error_type`, on delete RESTRICT | Type of the mistake. NULL for a correct answer and until the type is determined. |
| `competition_participation_id` | bigint | yes | FK → `core.competition_participation`, on delete SET NULL | Participation in a competition within which the answer was given. NULL for an ordinary answer. |
| `shown_as_exercise_type_id` | bigint | yes | FK → `core.exercise_type`, on delete RESTRICT | Exercise type in which the task was shown. NULL when it was shown in the own type of the exercise. |
| `audio_location` | text | yes |  | Address of the audio recording. NULL when the answer is not audio. |
| `reviewed_at` | timestamp with time zone | yes |  | Moment the answer was reviewed by a person. NULL for an answer checked automatically. |

Constraints:

- `pk_answer`: `PRIMARY KEY (id)`
- `fk_answer__competition_participation`: `FOREIGN KEY (competition_participation_id) REFERENCES core.competition_participation(id) ON DELETE SET NULL`
- `fk_answer__error_type`: `FOREIGN KEY (error_type_id) REFERENCES core.error_type(id) ON DELETE RESTRICT`
- `fk_answer__homework_assignment`: `FOREIGN KEY (homework_assignment_id) REFERENCES core.homework_assignment(id) ON DELETE SET NULL`
- `fk_answer__learning_link`: `FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE`
- `fk_answer__lesson_exercise`: `FOREIGN KEY (lesson_exercise_id) REFERENCES core.lesson_exercise(id) ON DELETE SET NULL`
- `fk_answer__shown_as_exercise_type`: `FOREIGN KEY (shown_as_exercise_type_id) REFERENCES core.exercise_type(id) ON DELETE RESTRICT`
- `fk_answer__task`: `FOREIGN KEY (task_id) REFERENCES core.task(id) ON DELETE CASCADE`
- `ck_answer__active_time_within_response`: `CHECK ((active_time_ms <= response_time_ms))`
- `ck_answer__answer_change_count_not_negative`: `CHECK ((answer_change_count >= 0))`
- `ck_answer__answer_rating`: `CHECK ((answer_rating = ANY (ARRAY['error'::text, 'slow_and_changed'::text, 'moderate'::text, 'fast'::text])))`
- `ck_answer__attempt_number_positive`: `CHECK ((attempt_number >= 1))`
- `ck_answer__response_time_not_negative`: `CHECK ((response_time_ms >= 0))`
- `ck_answer__result`: `CHECK ((result = ANY (ARRAY['correct'::text, 'incorrect'::text, 'awaiting_review'::text])))`

Indexes besides those behind the constraints:

- `ix_answer__competition_participation`: `(competition_participation_id)`
- `ix_answer__homework_assignment`: `(homework_assignment_id)`
- `ix_answer__learning_link_answered_at`: `(learning_link_id, answered_at)`
- `ix_answer__lesson_exercise`: `(lesson_exercise_id)`
- `ix_answer__task`: `(task_id)`

### core.revision_record

Spaced repetition schedule of one task for one learning link.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `task_id` | bigint | no | FK → `core.task`, on delete CASCADE | Task to revise. |
| `learning_link_id` | bigint | no | FK → `core.learning_link`, on delete CASCADE | Learning link of the learner. |
| `next_revision_date` | date | no |  | Date of the next revision. The daily queue is built by it. |
| `current_interval_days` | integer | no |  | Current interval in days. Grows after a correct answer. |
| `ease` | numeric(4,2), default `2.50` | no |  | Ease factor by which the interval grows after a correct answer. |
| `deferred_at` | timestamp with time zone | yes |  | Moment the task was deferred. NULL when it was never deferred. Not cleared when the task returns to the queue. |
| `deferral_end_date` | date | yes |  | Last day of the deferral. For a self-directed learner the system sets it 7 days ahead; for a learner with a teacher it is NULL until the teacher decides. The task is deferred now when deferred_at is filled and this date is NULL or not yet reached. |
| `part_id` | text | yes |  | Part of the task, the id from parts in the task body. NULL when the task has one part. |

Constraints:

- `pk_revision_record`: `PRIMARY KEY (id)`
- `uq_revision_record__link_task_part`: `UNIQUE NULLS NOT DISTINCT (learning_link_id, task_id, part_id)`
- `fk_revision_record__learning_link`: `FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE`
- `fk_revision_record__task`: `FOREIGN KEY (task_id) REFERENCES core.task(id) ON DELETE CASCADE`
- `ck_revision_record__ease_min`: `CHECK ((ease >= 1.30))`
- `ck_revision_record__interval_positive`: `CHECK ((current_interval_days >= 1))`
- `ck_revision_record__part_id_not_empty`: `CHECK ((part_id <> ''::text))`

Indexes besides those behind the constraints:

- `ix_revision_record__link_next_date`: `(learning_link_id, next_revision_date)`
- `ix_revision_record__task`: `(task_id)`

### core.topic_priority

Raised priority of a topic for a learning link: tasks of the topic come up more often until the end date.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `learning_link_id` | bigint | no | FK → `core.learning_link`, on delete CASCADE | Learning link the priority is raised for. |
| `topic_id` | bigint | no | FK → `core.topic`, on delete CASCADE | Topic whose priority is raised. |
| `raised_at` | timestamp with time zone | no |  | Moment the priority was raised. |
| `end_date` | date | no |  | Last day of the raised priority. Early cancellation is recorded as an end date equal to the current day. |

Constraints:

- `pk_topic_priority`: `PRIMARY KEY (id)`
- `fk_topic_priority__learning_link`: `FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE`
- `fk_topic_priority__topic`: `FOREIGN KEY (topic_id) REFERENCES core.topic(id) ON DELETE CASCADE`

Indexes besides those behind the constraints:

- `ix_topic_priority__learning_link`: `(learning_link_id)`
- `ix_topic_priority__topic`: `(topic_id)`

## History and level

The level of a learner on four scales, its changes, errors noticed in speech and notes of the teacher.

### core.scale_level

Level of a learner on one scale within one learning link.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `learning_link_id` | bigint | no | FK → `core.learning_link`, on delete CASCADE | Learning link the level belongs to. |
| `scale_id` | bigint | no | FK → `core.scale`, on delete RESTRICT | Scale. |
| `entry_cefr_level_id` | bigint | yes | FK → `core.cefr_level`, on delete RESTRICT | Level at the start of learning. NULL until set. |
| `current_cefr_level_id` | bigint | yes | FK → `core.cefr_level`, on delete RESTRICT | Current level. NULL while there is no data; shown as no data. |

Constraints:

- `pk_scale_level`: `PRIMARY KEY (id)`
- `uq_scale_level__pair`: `UNIQUE (learning_link_id, scale_id)`
- `fk_scale_level__current_cefr_level`: `FOREIGN KEY (current_cefr_level_id) REFERENCES core.cefr_level(id) ON DELETE RESTRICT`
- `fk_scale_level__entry_cefr_level`: `FOREIGN KEY (entry_cefr_level_id) REFERENCES core.cefr_level(id) ON DELETE RESTRICT`
- `fk_scale_level__learning_link`: `FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE`
- `fk_scale_level__scale`: `FOREIGN KEY (scale_id) REFERENCES core.scale(id) ON DELETE RESTRICT`

### core.level_change

Journal of level changes on a scale. A row is written once and is not changed afterwards, except for the moment it was shown to the learner.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `scale_level_id` | bigint | no | FK → `core.scale_level`, on delete CASCADE | Level on a scale that changed. Identifies both the learning link and the scale. |
| `previous_cefr_level_id` | bigint | no | FK → `core.cefr_level`, on delete RESTRICT | Level before the change. |
| `new_cefr_level_id` | bigint | no | FK → `core.cefr_level`, on delete RESTRICT | Level after the change. Differs from the previous level. |
| `changed_at` | timestamp with time zone | no |  | Moment of the change. |
| `changed_by` | text | no |  | Who made the change: system or user. Not a reference to a user. |
| `shown_to_learner_at` | timestamp with time zone | yes |  | Moment the congratulation was shown to the learner. NULL until it is shown. |

Constraints:

- `pk_level_change`: `PRIMARY KEY (id)`
- `fk_level_change__new_cefr_level`: `FOREIGN KEY (new_cefr_level_id) REFERENCES core.cefr_level(id) ON DELETE RESTRICT`
- `fk_level_change__previous_cefr_level`: `FOREIGN KEY (previous_cefr_level_id) REFERENCES core.cefr_level(id) ON DELETE RESTRICT`
- `fk_level_change__scale_level`: `FOREIGN KEY (scale_level_id) REFERENCES core.scale_level(id) ON DELETE CASCADE`
- `ck_level_change__changed_by`: `CHECK ((changed_by = ANY (ARRAY['system'::text, 'user'::text])))`
- `ck_level_change__levels_differ`: `CHECK ((new_cefr_level_id <> previous_cefr_level_id))`

Indexes besides those behind the constraints:

- `ix_level_change__scale_level`: `(scale_level_id)`

### core.oral_error

Oral error of a learner, recorded by the teacher during a lesson.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `learning_link_id` | bigint | no | FK → `core.learning_link`, on delete CASCADE | Learning link of the learner. |
| `lesson_id` | bigint | yes | FK → `core.lesson`, on delete SET NULL | Lesson during which the error was recorded. Becomes NULL when the lesson is deleted. |
| `task_id` | bigint | yes | FK → `core.task`, on delete SET NULL | Task that was open at that moment. May be NULL. |
| `topic_id` | bigint | yes | FK → `core.topic`, on delete SET NULL | Topic of the error. Taken from the current task; the teacher can change it. |
| `scale_id` | bigint | no | FK → `core.scale`, on delete RESTRICT | Scale the error relates to. Speech by default. |
| `phrase` | text | yes |  | Word or phrase with the error. Optional; can be added after the lesson. |
| `recorded_at` | timestamp with time zone | no |  | Moment the error was recorded. |
| `error_type_id` | bigint | yes | FK → `core.error_type`, on delete RESTRICT | Type of the mistake. NULL until it is specified. |

Constraints:

- `pk_oral_error`: `PRIMARY KEY (id)`
- `fk_oral_error__error_type`: `FOREIGN KEY (error_type_id) REFERENCES core.error_type(id) ON DELETE RESTRICT`
- `fk_oral_error__learning_link`: `FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE`
- `fk_oral_error__lesson`: `FOREIGN KEY (lesson_id) REFERENCES core.lesson(id) ON DELETE SET NULL`
- `fk_oral_error__scale`: `FOREIGN KEY (scale_id) REFERENCES core.scale(id) ON DELETE RESTRICT`
- `fk_oral_error__task`: `FOREIGN KEY (task_id) REFERENCES core.task(id) ON DELETE SET NULL`
- `fk_oral_error__topic`: `FOREIGN KEY (topic_id) REFERENCES core.topic(id) ON DELETE SET NULL`

Indexes besides those behind the constraints:

- `ix_oral_error__learning_link`: `(learning_link_id)`
- `ix_oral_error__lesson`: `(lesson_id)`
- `ix_oral_error__task`: `(task_id)`
- `ix_oral_error__topic`: `(topic_id)`

### core.note

Note of a teacher about a learner.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `learning_link_id` | bigint | no | FK → `core.learning_link`, on delete CASCADE | Learning link the note belongs to. |
| `lesson_id` | bigint | yes | FK → `core.lesson`, on delete SET NULL | Lesson the note was written at. May be NULL. |
| `note_text` | text | no |  | Personal data. Free text about the learner. |
| `written_at` | timestamp with time zone | no |  | Moment the note was written. |

Constraints:

- `pk_note`: `PRIMARY KEY (id)`
- `fk_note__learning_link`: `FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE`
- `fk_note__lesson`: `FOREIGN KEY (lesson_id) REFERENCES core.lesson(id) ON DELETE SET NULL`

Indexes besides those behind the constraints:

- `ix_note__learning_link`: `(learning_link_id)`
- `ix_note__lesson`: `(lesson_id)`

## Adaptation

What the system proposes to give next, to make harder or to return to revision.

### core.adaptation_proposal

Proposal of what to do next for a learner. Nothing is assigned until a decision is made.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `learning_link_id` | bigint | no | FK → `core.learning_link`, on delete CASCADE | Learning link the proposal is built for. |
| `generated_at` | timestamp with time zone | no |  | Moment the proposal was generated. |
| `status` | text | no |  | Status: proposed, approved, modified or assigned. |
| `decided_by` | text | yes |  | Who made the decision: system or user. NULL until a decision is made. |
| `decided_at` | timestamp with time zone | yes |  | Moment of the decision. NULL until a decision is made. |

Constraints:

- `pk_adaptation_proposal`: `PRIMARY KEY (id)`
- `fk_adaptation_proposal__learning_link`: `FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE`
- `ck_adaptation_proposal__decided_by`: `CHECK ((decided_by = ANY (ARRAY['system'::text, 'user'::text])))`
- `ck_adaptation_proposal__decision_complete`: `CHECK (((decided_by IS NULL) = (decided_at IS NULL)))`
- `ck_adaptation_proposal__status`: `CHECK ((status = ANY (ARRAY['proposed'::text, 'approved'::text, 'modified'::text, 'assigned'::text])))`
- `ck_adaptation_proposal__status_matches_decision`: `CHECK (((status = 'proposed'::text) = (decided_by IS NULL)))`

Indexes besides those behind the constraints:

- `ix_adaptation_proposal__learning_link`: `(learning_link_id)`

### core.adaptation_proposal_item

One item of an adaptation proposal: an exercise and what to do with it.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `adaptation_proposal_id` | bigint | no | FK → `core.adaptation_proposal`, on delete CASCADE | Proposal the item belongs to. |
| `item_kind` | text | no |  | Kind: give_next, return_to_revision, make_easier or make_harder. |
| `exercise_id` | bigint | no | FK → `core.exercise`, on delete CASCADE | Exercise the item is about. |
| `rationale_topic_id` | bigint | yes | FK → `core.topic`, on delete SET NULL | Topic the rationale is based on. NULL for an item added by a user. |
| `rationale_period_from` | date | yes |  | Start of the period the rationale is based on. NULL for an item added by a user. |
| `rationale_period_to` | date | yes |  | End of the period the rationale is based on. NULL for an item added by a user. |
| `added_by` | text | no |  | Who added the item: system or user. |
| `is_accepted` | boolean, default `true` | no |  | False when the user rejected the item. A rejected item stays in the record but is not given to the learner. |
| `shown_as_exercise_type_id` | bigint | yes | FK → `core.exercise_type`, on delete RESTRICT | Exercise type the exercise is shown in. Filled only for make_easier and make_harder. |

Constraints:

- `pk_adaptation_proposal_item`: `PRIMARY KEY (id)`
- `uq_adaptation_proposal_item__pair`: `UNIQUE (adaptation_proposal_id, exercise_id)`
- `fk_adaptation_proposal_item__adaptation_proposal`: `FOREIGN KEY (adaptation_proposal_id) REFERENCES core.adaptation_proposal(id) ON DELETE CASCADE`
- `fk_adaptation_proposal_item__exercise`: `FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE`
- `fk_adaptation_proposal_item__rationale_topic`: `FOREIGN KEY (rationale_topic_id) REFERENCES core.topic(id) ON DELETE SET NULL`
- `fk_adaptation_proposal_item__shown_as_exercise_type`: `FOREIGN KEY (shown_as_exercise_type_id) REFERENCES core.exercise_type(id) ON DELETE RESTRICT`
- `ck_adaptation_proposal_item__added_by`: `CHECK ((added_by = ANY (ARRAY['system'::text, 'user'::text])))`
- `ck_adaptation_proposal_item__item_kind`: `CHECK ((item_kind = ANY (ARRAY['give_next'::text, 'return_to_revision'::text, 'make_easier'::text, 'make_harder'::text])))`
- `ck_adaptation_proposal_item__period`: `CHECK ((((rationale_period_from IS NULL) AND (rationale_period_to IS NULL)) OR (rationale_period_from <= rationale_period_to)))`
- `ck_adaptation_proposal_item__shown_type_only_for_change`: `CHECK (((shown_as_exercise_type_id IS NULL) OR (item_kind = ANY (ARRAY['make_easier'::text, 'make_harder'::text]))))`
- `ck_adaptation_proposal_item__system_has_rationale`: `CHECK (((added_by <> 'system'::text) OR (rationale_period_from IS NOT NULL)))`

Indexes besides those behind the constraints:

- `ix_adaptation_proposal_item__exercise`: `(exercise_id)`
- `ix_adaptation_proposal_item__rationale_topic`: `(rationale_topic_id)`

## Competitions

Competitions in a lesson and between learners of the same level.

### core.competition

Competition: either held in a lesson on one exercise, or matched by the system among learners of equal level. Correctness is scored, not speed. The state is derived from the dates.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `lesson_id` | bigint | yes | FK → `core.lesson`, on delete CASCADE | Lesson the competition is held in. NULL for a competition outside a lesson. |
| `scale_id` | bigint | yes | FK → `core.scale`, on delete RESTRICT | Scale by which equal participants are matched. Filled only outside a lesson. |
| `cefr_level_id` | bigint | yes | FK → `core.cefr_level`, on delete RESTRICT | Level of the participants. Only outside a lesson; NULL for a competition composed by a teacher. |
| `exercise_type_id` | bigint | yes | FK → `core.exercise_type`, on delete RESTRICT | Exercise type familiar to all participants. Filled only outside a lesson. |
| `answer_time_limit_ms` | integer, default `240000` | no |  | Time allowed for one answer, in milliseconds. A ceiling, not a race: there is no countdown and speed is not scored. When it expires the task counts as unanswered. |
| `started_at` | timestamp with time zone | no |  | Moment the competition started. |
| `ended_at` | timestamp with time zone | yes |  | Moment the competition ended. NULL while it is in progress. |
| `exercise_id` | bigint | yes | FK → `core.exercise`, on delete CASCADE | Exercise the competition is held on. Filled only in a lesson. |
| `practice_task_count` | integer, default `1` | no |  | Number of practice tasks before the scored ones. |
| `scored_task_count` | integer | yes |  | Number of scored tasks. Outside a lesson it is required, 10 by default; in a lesson it is NULL: all tasks of the exercise after the practice ones are scored. |

Constraints:

- `pk_competition`: `PRIMARY KEY (id)`
- `fk_competition__cefr_level`: `FOREIGN KEY (cefr_level_id) REFERENCES core.cefr_level(id) ON DELETE RESTRICT`
- `fk_competition__exercise`: `FOREIGN KEY (exercise_id) REFERENCES core.exercise(id) ON DELETE CASCADE`
- `fk_competition__exercise_type`: `FOREIGN KEY (exercise_type_id) REFERENCES core.exercise_type(id) ON DELETE RESTRICT`
- `fk_competition__lesson`: `FOREIGN KEY (lesson_id) REFERENCES core.lesson(id) ON DELETE CASCADE`
- `fk_competition__scale`: `FOREIGN KEY (scale_id) REFERENCES core.scale(id) ON DELETE RESTRICT`
- `ck_competition__answer_time_limit_positive`: `CHECK ((answer_time_limit_ms > 0))`
- `ck_competition__ended_after_started`: `CHECK ((ended_at >= started_at))`
- `ck_competition__lesson_or_matched`: `CHECK ((((lesson_id IS NOT NULL) AND (exercise_id IS NOT NULL) AND (scale_id IS NULL) AND (cefr_level_id IS NULL) AND (exercise_type_id IS NULL) AND (scored_task_count IS NULL)) OR ((lesson_id IS NULL) AND (exercise_id IS NULL) AND (scale_id IS NOT NULL) AND (exercise_type_id IS NOT NULL) AND (scored_task_count IS NOT NULL))))`
- `ck_competition__practice_task_count_not_negative`: `CHECK ((practice_task_count >= 0))`
- `ck_competition__scored_task_count_positive`: `CHECK ((scored_task_count > 0))`

Indexes besides those behind the constraints:

- `ix_competition__exercise`: `(exercise_id)`
- `ix_competition__lesson`: `(lesson_id)`

### core.competition_participation

Participation of a learner in a competition. A learner joins only by own action.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `competition_id` | bigint | no | FK → `core.competition`, on delete CASCADE | Competition. |
| `learning_link_id` | bigint | no | FK → `core.learning_link`, on delete CASCADE | Learning link of the participant. |
| `nickname` | text | yes |  | Nickname shown to other participants, unique within the competition. NULL in a lesson. |
| `team_number` | integer | yes |  | Team number. NULL when everyone competes individually. |
| `joined_at` | timestamp with time zone | no |  | Moment the learner joined. |

Constraints:

- `pk_competition_participation`: `PRIMARY KEY (id)`
- `uq_competition_participation__nickname`: `UNIQUE (competition_id, nickname)`
- `uq_competition_participation__pair`: `UNIQUE (competition_id, learning_link_id)`
- `fk_competition_participation__competition`: `FOREIGN KEY (competition_id) REFERENCES core.competition(id) ON DELETE CASCADE`
- `fk_competition_participation__learning_link`: `FOREIGN KEY (learning_link_id) REFERENCES core.learning_link(id) ON DELETE CASCADE`
- `ck_competition_participation__team_number_positive`: `CHECK ((team_number > 0))`

Indexes besides those behind the constraints:

- `ix_competition_participation__learning_link`: `(learning_link_id)`

## Anonymous statistics (schema stats)

Events without personal data, linked to a learning link only through a random code.

### stats.statistics_event

Anonymised event written when a learner answers a task. Contains no personal data and is never updated.

| Column | Type | Null | Key | Description |
|---|---|---|---|---|
| `id` | bigint, identity | no | PK | Surrogate key. |
| `link_code` | uuid | no |  | Random code of the learning link. A plain value, not a reference, so the event survives the erasure of personal data. |
| `exercise_type_id` | bigint | no | FK → `core.exercise_type`, on delete RESTRICT | Exercise type. |
| `topic_id` | bigint | yes | FK → `core.topic`, on delete RESTRICT | Topic, only when it is from the common catalogue. NULL for a topic created by a user. |
| `is_correct` | boolean | no |  | True when the answer was correct. |
| `attempt_number` | integer | no |  | Number of the attempt. |
| `time_bucket` | text | no |  | Conclusion about speed: fast, moderate or slow. The exact response time is not stored. |
| `scale_id` | bigint | no | FK → `core.scale`, on delete RESTRICT | Scale the exercise trains. |
| `cefr_level_id` | bigint | no | FK → `core.cefr_level`, on delete RESTRICT | Level of the learner on that scale at the moment of the event. |
| `device_type` | text | no |  | Device type: desktop, tablet or mobile. |
| `event_date` | date | no |  | Day of the event. The exact time is not stored. |

Constraints:

- `pk_statistics_event`: `PRIMARY KEY (id)`
- `fk_statistics_event__cefr_level`: `FOREIGN KEY (cefr_level_id) REFERENCES core.cefr_level(id) ON DELETE RESTRICT`
- `fk_statistics_event__exercise_type`: `FOREIGN KEY (exercise_type_id) REFERENCES core.exercise_type(id) ON DELETE RESTRICT`
- `fk_statistics_event__scale`: `FOREIGN KEY (scale_id) REFERENCES core.scale(id) ON DELETE RESTRICT`
- `fk_statistics_event__topic`: `FOREIGN KEY (topic_id) REFERENCES core.topic(id) ON DELETE RESTRICT`
- `ck_statistics_event__attempt_number_positive`: `CHECK ((attempt_number >= 1))`
- `ck_statistics_event__device_type`: `CHECK ((device_type = ANY (ARRAY['desktop'::text, 'tablet'::text, 'mobile'::text])))`
- `ck_statistics_event__time_bucket`: `CHECK ((time_bucket = ANY (ARRAY['fast'::text, 'moderate'::text, 'slow'::text])))`

Indexes besides those behind the constraints:

- `ix_statistics_event__event_date`: `(event_date)`
- `ix_statistics_event__link_code`: `(link_code)`
- `ix_statistics_event__topic`: `(topic_id)`

