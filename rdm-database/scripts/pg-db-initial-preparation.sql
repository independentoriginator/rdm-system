CREATE ROLE rdm_system LOGIN password 'rdm_system';
CREATE DATABASE rdm_system ENCODING 'UTF8' OWNER rdm_system;
\connect postgres://rdm_system:rdm_system@localhost/rdm_system;
CREATE SCHEMA rdm_system AUTHORIZATION rdm_system;