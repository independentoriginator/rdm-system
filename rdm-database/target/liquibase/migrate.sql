-- *********************************************************************
-- Update Database Script
-- *********************************************************************
-- Change Log: src/main/db.changelog-master.xml
-- Ran at: 1/4/22, 9:27 PM
-- Against: rdm_system@jdbc:postgresql://localhost:5432/rdm_system
-- Liquibase version: 4.6.2
-- *********************************************************************

-- Lock Database
UPDATE databasechangeloglock SET LOCKED = TRUE, LOCKEDBY = '192.168.0.42 (192.168.0.42)', LOCKGRANTED = '2022-01-04 21:27:09.63' WHERE ID = 1 AND LOCKED = FALSE;

-- Changeset src/main/releases/0.1/004-language.xml::initial-languages-names::rsafiullin
INSERT INTO language_lc (type_id, attr_id, lang_id, lc_string) VALUES ((select id from language where tag = 'ru'), (     select       a.id     from       meta_type t      join meta_attribute a       on a.meta_type_id = t.id      where       t.internal_name = 'language'      and a.internal_name = 'name'    ), (select id from language where tag = 'ru'), 'Русский');

INSERT INTO language_lc (type_id, attr_id, lang_id, lc_string) VALUES ((select id from language where tag = 'ru'), (     select       a.id     from       meta_type t      join meta_attribute a       on a.meta_type_id = t.id      where       t.internal_name = 'language'      and a.internal_name = 'name'    ), (select id from language where tag = 'en'), 'Russian');

INSERT INTO language_lc (type_id, attr_id, lang_id, lc_string) VALUES ((select id from language where tag = 'en'), (     select       a.id     from       meta_type t      join meta_attribute a       on a.meta_type_id = t.id      where       t.internal_name = 'language'      and a.internal_name = 'name'    ), (select id from language where tag = 'en'), 'English');

INSERT INTO databasechangelog (ID, AUTHOR, FILENAME, DATEEXECUTED, ORDEREXECUTED, MD5SUM, DESCRIPTION, COMMENTS, EXECTYPE, CONTEXTS, LABELS, LIQUIBASE, DEPLOYMENT_ID) VALUES ('initial-languages-names', 'rsafiullin', 'src/main/releases/0.1/004-language.xml', NOW(), 22, '8:095270b60b770165d7ff87eaf234e568', 'insert tableName=language_lc; insert tableName=language_lc; insert tableName=language_lc', '', 'EXECUTED', NULL, NULL, '4.6.2', '1313633086');

-- Changeset src/main/releases/0.1/005-meta_type-name.xml::meta_type-localised-names::rsafiullin
INSERT INTO meta_type_lc (type_id, attr_id, lang_id, lc_string) VALUES ((select id from meta_type where internal_name = 'meta_type'), (     select       a.id     from       meta_type t      join meta_attribute a       on a.meta_type_id = t.id      where       t.internal_name = 'meta_type'      and a.internal_name = 'name'    ), (select id from language where tag = 'ru'), 'Метатип');

INSERT INTO meta_type_lc (type_id, attr_id, lang_id, lc_string) VALUES ((select id from meta_type where internal_name = 'meta_type'), (     select       a.id     from       meta_type t      join meta_attribute a       on a.meta_type_id = t.id      where       t.internal_name = 'meta_type'      and a.internal_name = 'name'    ), (select id from language where tag = 'en'), 'Meta type');

INSERT INTO meta_attribute_lc (type_id, attr_id, lang_id, lc_string) VALUES ((select id from meta_type where internal_name = 'meta_attribute'), (     select       a.id     from       meta_type t      join meta_attribute a       on a.meta_type_id = t.id      where       t.internal_name = 'meta_attribute'      and a.internal_name = 'name'    ), (select id from language where tag = 'ru'), 'Метаатрибут');

INSERT INTO meta_attribute_lc (type_id, attr_id, lang_id, lc_string) VALUES ((select id from meta_type where internal_name = 'meta_attribute'), (     select       a.id     from       meta_type t      join meta_attribute a       on a.meta_type_id = t.id      where       t.internal_name = 'meta_attribute'      and a.internal_name = 'name'    ), (select id from language where tag = 'en'), 'Meta attribute');

INSERT INTO databasechangelog (ID, AUTHOR, FILENAME, DATEEXECUTED, ORDEREXECUTED, MD5SUM, DESCRIPTION, COMMENTS, EXECTYPE, CONTEXTS, LABELS, LIQUIBASE, DEPLOYMENT_ID) VALUES ('meta_type-localised-names', 'rsafiullin', 'src/main/releases/0.1/005-meta_type-name.xml', NOW(), 23, '8:1fbb31c683a2d255ae52b807270bbac0', 'insert tableName=meta_type_lc; insert tableName=meta_type_lc; insert tableName=meta_attribute_lc; insert tableName=meta_attribute_lc', '', 'EXECUTED', NULL, NULL, '4.6.2', '1313633086');

-- Changeset src/main/db.changelog-master.xml::build target tables::rsafiullin
call p_build_target_tables();

INSERT INTO databasechangelog (ID, AUTHOR, FILENAME, DATEEXECUTED, ORDEREXECUTED, MD5SUM, DESCRIPTION, COMMENTS, EXECTYPE, CONTEXTS, LABELS, LIQUIBASE, DEPLOYMENT_ID) VALUES ('build target tables', 'rsafiullin', 'src/main/db.changelog-master.xml', NOW(), 24, '8:ca7d52ffcb46e44e55740ba5cf533bd5', 'sql', '', 'EXECUTED', NULL, NULL, '4.6.2', '1313633086');

-- Release Database Lock
UPDATE databasechangeloglock SET LOCKED = FALSE, LOCKEDBY = NULL, LOCKGRANTED = NULL WHERE ID = 1;

