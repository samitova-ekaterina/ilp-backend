# Personal data

ILP is used by learners from the age of 14, so the handling of personal data is part of the design and not an addition to it. This document says which data are personal, who can see them, how they leave the system and why the statistics cannot be traced back to a person.

## What is stored and what is not

The system deliberately stores little. There is no date of birth, only an age group of two values; there is no postal address, no phone number and no payment data. A user is identified by an e-mail address and may give a name that other users see.

| Column | What it is | Marked in the database |
|---|---|---|
| `core.app_user.email` | E-mail address, the login | Comment starts with "Personal data" |
| `core.app_user.display_name` | Name shown to other users; may be empty | Comment starts with "Personal data" |
| `core.note.note_text` | Free text a teacher writes about a learner | Comment starts with "Personal data" |
| `core.app_user.password_hash` | Argon2id hash of the password | Not personal data, but secret |

The mark in the comment is not decoration. The masking views and the rights of the reading role were built by going through these marks, and a new personal column is expected to carry the same mark.

Consent is stored as a history. Each row of `core.consent` records the kind of consent, the version of the policy it was given to, when it was given and when it was withdrawn. The consent age of the country of the user is taken from `core.country`, and consent to statistics is a separate kind that is not given by default for users aged 14 to 17.

## Masking

The reading role has no right to read the three personal columns. Instead it reads two views.

| View | What it shows |
|---|---|
| `core.v_app_user_masked` | `b***@example.com` instead of the address and `B***` instead of the name; an empty name stays empty. The non-personal columns are shown as they are |
| `core.v_note_masked` | The length of the text instead of the text |

The domain of the address is kept because support needs to tell a mistyped address from a working one, and one letter of the name is enough to recognise a record in a conversation with the user. Both views are created with `security_barrier`, which prevents a query condition from being evaluated before the masking and leaking the hidden value.

Masking protects against a reader of the database. The application itself works with the writing role and sees real values, because it has to send e-mails and show names.

## Erasure

A user may erase one learning link or the whole account. The request is stored in `core.erasure_request` and must be confirmed through a link sent by e-mail; an unconfirmed request is never executed. The procedure `core.erase_personal_data` executes a confirmed request in a single transaction.

### What is erased immediately

| What | When |
|---|---|
| The account, the e-mail address, the name and the password hash | Immediately |
| Everything that belongs to a learner: answers, revision records, levels, notes about the learner, consents | Immediately |
| The row that links a learning link to its statistics code | Immediately |
| Materials of a teacher that nobody else worked with | Immediately |

### What is kept for a limited time

A material of a teacher that learners worked with is the one exception, and it is a decision of the product, not a side effect. If it disappeared at once, the answers of the learners to its exercises would disappear with it and without warning. Such a material therefore stays for a limited time, with no owner: the account of the teacher is already gone, and the row keeps only the day until which it is retained.

| Question | Answer |
|---|---|
| Which materials are kept | Those for whose exercises another person has an answer or a revision record |
| For how long | Seven days by default. The teacher may choose from 0 to 365 days in the erasure request; 0 means "erase at once" |
| What the learner can do meanwhile | See the history and go on revising what was already studied; the links closed by the erasure receive the same period of access |
| How the learner knows | The view `core.v_material_expiring` lists, for every learning link, the materials that will be deleted, the last day and the number of answers and revision records that go with them |
| What happens afterwards | The procedure `core.purge_retained_materials`, meant to run once a day, deletes the materials whose period is over together with their exercises, answers and revision records. The levels of the learner remain |

Two limits of this mechanism should be stated plainly. The material loses its owner in the database, but the PDF file is not rewritten: if the author's name is printed on a page, it stays there until the file is deleted. And homework that the teacher assigned and the learner had not finished is removed at once, because it is recorded on the teacher.

### What the procedure takes care of

A plain `DELETE` of a user fails in two real cases, and the procedure exists partly because of them. A user who created a private topic and attached exercises to it cannot be deleted directly, since an exercise forbids the deletion of its topic; and a teacher with open links cannot be deleted directly, since an open link must have its teacher. The procedure closes the links, removes or retains the materials, detaches what still points to the private topics, deletes folders from the innermost outwards and only then deletes the user.

The request itself is kept, without the user, in the state `executed` and with the hash of the confirmation code cleared. It is the evidence that the erasure was requested, confirmed and done.

## The same idea when lessons simply end

Erasure is the rare case. Much more often a teacher and a learner stop working together while both stay in the system. The link is closed, not deleted. The teacher keeps the archive of results on the teacher's own assignments and sees nothing the learner does afterwards. The learner keeps the history without a time limit, because the answers belong to the learner.

What would stop is revision: the exercises belong to the teacher. The teacher may therefore leave the learner access for up to 365 days when closing the link. The last day is stored in `learning_link.access_until`, and the revision queue includes a closed link until that day. Without a choice no access is left.

## Anonymous statistics

Statistics are kept in a separate schema and contain no personal column at all. An event records the exercise type, the topic, whether the answer was correct, the attempt number, a speed bucket of three values instead of seconds, the scale, the level, the type of device and the day.

| Measure | How it works |
|---|---|
| No reference to a person | `stats.statistics_event` has no foreign key to a user or a learning link. It holds a random `uuid`, a plain value |
| The key is kept elsewhere | `core.learning_link_pseudonym` maps a learning link to its code. It lives in the other schema and is closed to the reading role |
| The key is destroyed with the data | The row of the mapping is deleted with the learning link. From that moment no query can connect the events to a person |
| Coarse values | A day instead of a moment, a speed bucket instead of milliseconds, a level instead of a score |
| Private topics | When a user is erased, events that pointed to the user's private topics lose the topic, since the name of a private topic could describe its owner |
| Consent | The application writes events only for a user whose consent to statistics is in force |

The events stay after an erasure. This is intended and is what the acceptance criterion of the product asks for: anonymous statistics are preserved without a way to link them to a person. The monthly summary `stats.mv_statistics_summary` shows for every group how many different learning links stand behind the number, so that a figure resting on one learner is not mistaken for a pattern.

## Backups

Erasure from the working database is immediate, apart from the retained materials described above. Backups are an operational matter outside the database structure: according to the requirements of the product they are made daily, stored within the European Union and kept for at most 30 days, after which erased data are gone from them as well.
