-- ".read schema.sql" in "sqlite3" to create the database.  A pre-created version
-- of the database is shipped in jarvis/demo/db/demo.db for your convenience.
--
DROP TABLE boat;
DROP TABLE boat_class;
DROP TABLE users;

CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    change_user text NOT NULL REFERENCES users (name) ON DELETE RESTRICT ON UPDATE CASCADE,
    change_date timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,

    name text UNIQUE NOT NULL CHECK (name <> ''),
    password text);

INSERT INTO users (name, password, change_user) VALUES ('admin', 'admin', 'admin');
INSERT INTO users (name, password, change_user) VALUES ('guest', 'guest', 'admin');

-- This is for a class of boat.
CREATE TABLE boat_class (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    change_user text NOT NULL REFERENCES users (name) ON DELETE RESTRICT ON UPDATE CASCADE,
    change_date timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,

    class text UNIQUE NOT NULL CHECK (class <> ''),
    active text NOT NULL CHECK (active = 'Y' OR active = 'N'),
    description text);

INSERT INTO boat_class (class, active, description, change_user)
    VALUES ('X Class', 'N', 'Product of a deranged mind.', 'admin');

INSERT INTO boat_class (class, active, description, change_user)
    VALUES ('Racing Rapid', 'Y', 'Swept-wing dual-overhead lift-ratchet proposal.
This boat class is far from production-ready.', 'admin');

INSERT INTO boat_class (class, active, description, change_user)
    VALUES ('Makkleson', 'Y', 'Suitable for infants and those of timid heart.', 'admin');

-- And this is for individual boats.
CREATE TABLE boat (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    change_user text NOT NULL REFERENCES users (name) ON DELETE RESTRICT ON UPDATE CASCADE,
    change_date timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,

    name text NOT NULL CHECK (name <> ''),
    registration_num integer DEFAULT 0,
    class text NOT NULL REFERENCES boat_class (class) ON DELETE RESTRICT ON UPDATE CASCADE,
    owner text,
    description text,
    UNIQUE (class, name));

INSERT INTO boat (name, registration_num, class, owner, change_user)
    VALUES ('MyMakk', 33, 'Makklesons', 'John Smith', 'admin');

INSERT INTO boat (name, registration_num, class, owner, change_user)
    VALUES ('Mr. Makkles IV', 104, 'Makklesons', 'John Smith, Jr.', 'admin');

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

