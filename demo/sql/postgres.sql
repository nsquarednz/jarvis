-- Run this script as postgres (or other privileged user) to create the 'botany'
-- database instance for the demo.  Jarvis should work with any DBD-supported
-- database, though this script will need adapting.
--
CREATE DATABASE jarvis_demo;
\connect jarvis_demo;

CREATE ROLE "www-data" WITH LOGIN;
CREATE ROLE "admin";
GRANT "admin" TO "www-data";


-- This table is used to determine who can login.
CREATE TABLE users (
    id serial,
    change_user text NOT NULL REFERENCES users (name) ON DELETE RESTRICT ON UPDATE CASCADE,
    change_date timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,

    name text UNIQUE NOT NULL CHECK (name <> ''),
    password text);

GRANT SELECT, INSERT, UPDATE, DELETE ON users TO admin;
GRANT UPDATE ON SEQUENCE users_id_seq TO admin;

INSERT INTO users (name, password, change_user) VALUES ('admin', 'admin', 'admin');

INSERT INTO users (name, password, change_user) VALUES ('guest', 'guest', 'admin');

-- This is for a class of boat.
CREATE TABLE boat_class (
    id serial,
    change_user text NOT NULL REFERENCES users (name) ON DELETE RESTRICT ON UPDATE CASCADE,
    change_date timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,

    class text UNIQUE NOT NULL CHECK (class <> ''),
    active text NOT NULL CHECK (active = 'Y' OR active = 'N'),
    description text);

GRANT SELECT, INSERT, UPDATE, DELETE ON boat_class TO admin;
GRANT UPDATE ON SEQUENCE boat_class_id_seq TO admin;

INSERT INTO boat_class (class, active, description, change_user)
    VALUES ('X Class', 'N', 'Product of a deranged mind.', 'admin');

INSERT INTO boat_class (class, active, description, change_user)
    VALUES ('Racing Rapid', 'Y', 'Swept-wing dual-overhead lift-ratchet proposal.
This boat class is far from production-ready.', 'admin');

INSERT INTO boat_class (class, active, description, change_user)
    VALUES ('Makkleson', 'Y', 'Suitable for infants and those of timid heart.', 'admin');

-- And this is for individual boats.
CREATE TABLE boat (
    id serial,
    change_user text NOT NULL REFERENCES users (name) ON DELETE RESTRICT ON UPDATE CASCADE,
    change_date timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,

    name text NOT NULL CHECK (name <> ''),
    registration_num integer DEFAULT 0,
    class text NOT NULL REFERENCES boat_class (class) ON DELETE RESTRICT ON UPDATE CASCADE,
    owner text,
    description text,
    PRIMARY KEY (class, name));

GRANT SELECT, INSERT, UPDATE, DELETE ON boat TO admin;
GRANT UPDATE ON SEQUENCE boat_id_seq TO admin;

INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Flying Fox II', 13423, 'X Class', 'Graham Parker', 'Pink and blue.', 'admin');

INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Mixed Emotions', 113, 'X Class', NULL, 'Historical, wood planked.', 'admin');

INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Epsilon', 0, 'X Class', 'J & F Wilson', 'Last of its breed.

This boat was built in 1959, and is the last remaining 
example of this classic class.', 'admin');

INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Randy', 4444, 'Racing Rapid', 'Peter Michael-Smythe', 'For sale, apply within.', 'admin');

INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Listerine', 31, 'Makkleson', NULL, 'Not currently in sailable condition.', 'admin');

