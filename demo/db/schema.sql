-- ".read schema.sql" in "sqlite3" to create the database.  A pre-created version
-- of the database is shipped in jarvis/demo/db/demo.db for your convenience.
--
DROP TABLE boat;
DROP TABLE boat_class;
DROP TABLE users;
DROP VIEW groups;

CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    change_user text NOT NULL REFERENCES users (name) ON DELETE RESTRICT ON UPDATE CASCADE,
    change_date timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,

    name text UNIQUE NOT NULL CHECK (name <> ''),
    password text NOT NULL CHECK (password <> ''),
    is_admin boolean DEFAULT false);

INSERT INTO users (name, password, is_admin, change_user) VALUES ('admin', 'admin', 1, 'admin');
INSERT INTO users (name, password, is_admin, change_user) VALUES ('guest', 'guest', 0, 'admin');

CREATE VIEW groups AS
    SELECT name, 'default' AS group_name FROM users
    UNION
    SELECT name, 'admin' AS group_name FROM users WHERE is_admin = 1;

-- This is for a class of boat.
CREATE TABLE boat_class (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    change_user text NOT NULL REFERENCES users (name) ON DELETE RESTRICT ON UPDATE CASCADE,
    change_date timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,

    class text UNIQUE NOT NULL CHECK (class <> ''),
    active text NOT NULL CHECK (active = 'Y' OR active = 'N'),
    description text);

INSERT INTO boat_class (class, active, description, change_user)
    VALUES ('Makkleson', 'Y', 'Suitable for infants and those of timid heart.', 'admin');

INSERT INTO boat_class (class, active, description, change_user)
    VALUES ('X Class', 'N', 'Product of a deranged mind.', 'admin');

INSERT INTO boat_class (class, active, description, change_user)
    VALUES ('Racing Rapid', 'Y', 'Swept-wing dual-overhead lift-ratchet proposal.
This boat class is far from production-ready.', 'admin');

INSERT INTO boat_class (class, active, description, change_user)
    VALUES ('SemiFlot', 'Y', 'Currently under review for watertight
issues.  Recommend only used for indoor sailing until
legal issues are resolved.', 'admin');

-- And this is for individual boats.
CREATE TABLE boat (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    change_user text NOT NULL REFERENCES users (name) ON DELETE RESTRICT ON UPDATE CASCADE,
    change_date timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,

    name text NOT NULL CHECK (name <> ''),
    registration_num integer,
    class text NOT NULL REFERENCES boat_class (class) ON DELETE RESTRICT ON UPDATE CASCADE,
    owner text,
    description text,
    UNIQUE (class, name));

INSERT INTO boat (name, registration_num, class, owner, change_user)
    VALUES ('MyMakk', 33, 'Makkleson', 'John Smith', 'admin');
INSERT INTO boat (name, registration_num, class, owner, change_user)
    VALUES ('Mr. Makkles IV', 104, 'Makkleson', 'John Smith, Jr.', 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Listerine', 31, 'Makkleson', NULL, 'Not currently in sailable condition.', 'admin');

INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Flying Fox II', 13423, 'X Class', 'Graham Parker', 'Pink and blue.', 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Mixed Emotions', 113, 'X Class', NULL, 'Historical, wood planked.', 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Epsilon', NULL, 'X Class', 'J & F Wilson', 'Last of its breed.

This boat was built in 1959, and is the last remaining
example of this classic class.', 'admin');

INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Randy', 4444, 'Racing Rapid', 'Peter Michael-Smythe', 'For sale, apply within.', 'admin');


INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Happy', 62, 'SemiFlot', 'Snow White', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Grumpy', 78, 'SemiFlot', 'Snow White', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Dopey', 103, 'SemiFlot', 'Snow White', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Bashful', 104, 'SemiFlot', 'Snow White', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Sleepy', 213, 'SemiFlot', 'Snow White', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Sneezy', 220, 'SemiFlot', 'Snow White', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Doc', 221, 'SemiFlot', 'Snow White', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Dasher', 319, 'SemiFlot', 'Santa Sailing School, Inc.', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Prancer', 331, 'SemiFlot', 'Santa Sailing School, Inc.', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Donner', 329, 'SemiFlot', 'Santa Sailing School, Inc.', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Blitzen', 310, 'SemiFlot', 'Santa Sailing School, Inc.', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 1', 401, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 2', 402, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 3', 403, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 4', 404, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 5', 405, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 6', 406, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 7', 407, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 8', 408, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 9', 409, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 10', 410, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 11', 411, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 12', 412, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 13', 413, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 14', 414, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 15', 415, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 16', 416, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 17', 417, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 18', 418, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 19', 419, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 20', 420, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 21', 421, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 22', 422, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 23', 423, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('RSYS 24', 424, 'SemiFlot', 'Royal Sydney Yahtzee Systems', NULL, 'admin');
INSERT INTO boat (name, registration_num, class, owner, description, change_user)
    VALUES ('Anonymous', NULL, 'SemiFlot', NULL, 'Found abandoned.  Seeking owner.', 'admin');
