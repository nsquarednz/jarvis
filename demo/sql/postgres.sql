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
    name text UNIQUE NOT NULL CHECK (name <> ''),
    password text);

GRANT SELECT, INSERT, UPDATE, DELETE ON users TO admin;
GRANT UPDATE ON SEQUENCE users_id_seq TO admin;

INSERT INTO users (name, password) VALUES ('guest', 'guest');

-- This is for a class of boat.
CREATE TABLE boat_class (
    id serial,
    class text UNIQUE NOT NULL CHECK (class <> ''),
    active text NOT NULL CHECK (active = 'Y' OR active = 'N'),
    description text);

GRANT SELECT, INSERT, UPDATE, DELETE ON boat_class TO admin;
GRANT UPDATE ON SEQUENCE boat_class_id_seq TO admin;

INSERT INTO boat_class (class, active, description)
    VALUES ('X Class', 'N', 'Product of a deranged mind.');

INSERT INTO boat_class (class, active, description)
    VALUES ('Racing Rapid', 'Y', 'Swept-wing dual-overhead lift-ratchet proposal.
This boat class is far from production-ready.');

INSERT INTO boat_class (class, active, description)
    VALUES ('Makkleson', 'Y', 'Suitable for infants and those of timid heart.');

-- And this is for individual boats.
CREATE TABLE boat (
    id serial,
    name text NOT NULL CHECK (name <> ''),
    registration_num integer DEFAULT 0,
    class text NOT NULL REFERENCES boat_class (class) ON DELETE RESTRICT ON UPDATE CASCADE,
    owner text,
    description text,
    PRIMARY KEY (class, name));

GRANT SELECT, INSERT, UPDATE, DELETE ON boat TO admin;
GRANT UPDATE ON SEQUENCE boat_id_seq TO admin;

INSERT INTO boat (name, registration_num, class, owner, description)
    VALUES ('Flying Fox II', 13423, 'X Class', 'Graham Parker', 'Pink and blue.');

INSERT INTO boat (name, registration_num, class, owner, description)
    VALUES ('Mixed Emotions', 113, 'X Class', NULL, 'Historical, wood planked.');

INSERT INTO boat (name, registration_num, class, owner, description)
    VALUES ('Epsilon', 0, 'X Class', 'J & F Wilson', 'Last of its breed.

This boat was built in 1959, and is the last remaining 
example of this classic class.');

INSERT INTO boat (name, registration_num, class, owner, description)
    VALUES ('Randy', 4444, 'Racing Rapid', 'Peter Michael-Smythe', 'For sale, apply within.');

INSERT INTO boat (name, registration_num, class, owner, description)
    VALUES ('Listerine', 31, 'Makkleson', NULL, 'Not currently in sailable condition.');

