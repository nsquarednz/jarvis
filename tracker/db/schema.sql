DROP TABLE request;
CREATE TABLE request (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sid TEXT,
    debug_level INTEGER,
    app_name TEXT,
    username TEXT,
    group_list TEXT,
    dataset TEXT,
    action TEXT,
    params TEXT,
    in_nrows INTEGER,
    out_nrows INTEGER,
    start_time JULIAN,
    duration_ms INTEGER
);

DROP TABLE error;
CREATE TABLE error (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sid TEXT,
    app_name TEXT,
    username TEXT,
    group_list TEXT,
    dataset TEXT,
    action TEXT,
    params TEXT,
    post_body TEXT,
    message TEXT,
    start_time JULIAN
);

CREATE INDEX request_start_time_idx on request (start_time);
