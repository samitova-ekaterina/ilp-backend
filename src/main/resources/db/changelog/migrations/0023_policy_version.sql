--liquibase formatted sql

--changeset samitava:0023-policy-version-data
INSERT INTO core.policy_version (version_number, effective_from, policy_text) VALUES
    ('1.0', DATE '2026-11-16',
'ILP Personal Data Processing Policy. Version 1.0. Effective from 16 November 2026.

1. Who processes the data. ILP is an educational project, a diploma thesis. The data are processed by the author of the project. Contact address: privacy@example.com.

2. What data are collected and why. Account: email address, password (stored only as a hash), role, country, age group and the consent mark. They are needed to sign in and to check the age of independent consent. The date of birth is not stored. An account cannot be created without an email address and a password. Other data appear as the service is used. Materials: uploaded PDF files and the exercises obtained from them. They do not leave the workspace of the person who uploaded them. The user is responsible for having the right to upload a material. Learning history: answers, results, attempts, response time, written mistakes and the revision queue. They are needed for the history, adaptation and revision. Learner card: oral mistakes, notes, level and goal. They are entered by the teacher and are visible only within the learning link. Summary by link: created by the learner to show to a third party. Email reminders: no more than one message a day, can be switched off. Special categories of personal data are not collected.

3. Legal basis. The account, materials, learning history, learner card and reminders are processed to provide the service (Article 6(1)(b) of the General Data Protection Regulation). The summary by link and the anonymised statistics are processed only with consent (Article 6(1)(a)).

4. Age. In Lithuania a person can give consent independently from the age of 14. For users aged 14 to 17 the consent to anonymised statistics is switched off by default.

5. Anonymised statistics. They are collected only with a separate consent and are needed to develop the product. An event contains no name, email address, answer text or audio. An event is linked to a random code and stores the day without the exact time. When the user data are erased, the link between the code and the person is destroyed, and after that the statistics are anonymous.

6. Storage periods. Account: until the account is deleted. Materials: until deleted by the owner. Learning history: until the learning link or the account is deleted. Learner card: until the learning link is deleted. Summary by link: until the period expires (it is set by the learner, 14 days by default) or until the link is revoked.

7. User rights. To access the data and to export them. To correct inaccurate data. To restrict the processing of the data and to object to it. To erase the data: the request is confirmed by email and is carried out within one month, and the data are removed from backups within 30 days. To withdraw consent at any time. To lodge a complaint with a data protection supervisory authority.

8. Where the data are stored. In the European Union.

9. Artificial intelligence and automated decisions. AI is not used for the content of tasks and answer keys and does not make decisions for the user. Everything added with the help of AI is marked. The system does not automatically make decisions that have legal effects for the user.

10. Changes to the policy. A new version is published with its number and effective date. The user consent is stored together with the policy version under which it was given.');
--rollback DELETE FROM core.policy_version WHERE version_number = '1.0';
