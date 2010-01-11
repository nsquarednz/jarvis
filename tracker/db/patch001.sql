-- Run with sqlite3> .read patch001.sql
ALTER TABLE request ADD COLUMN dataset_type TEXT (1);

CREATE TABLE login (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sid TEXT,
    username TEXT,
    logged_in INTEGER,
    error_string TEXT,
    group_list TEXT,
    start_time JULIAN
);
