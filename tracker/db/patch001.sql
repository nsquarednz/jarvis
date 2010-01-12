-- Run with sqlite3> .read patch001.sql
ALTER TABLE request ADD COLUMN dataset_type TEXT (1);

CREATE TABLE login (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sid TEXT,
    app_name TEXT,
    username TEXT,
    logged_in INTEGER,
    error_string TEXT,
    group_list TEXT,
    address TEXT,
    start_time JULIAN
);

CREATE TABLE tracker_user (
    username VARCHAR (50) NOT NULL PRIMARY KEY,
    password VARCHAR (50) NOT NULL,
    user_group VARCHAR (50) NOT NULL
);

