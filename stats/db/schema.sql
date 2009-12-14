DROP TABLE request;

CREATE TABLE request (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sid TEXT,
    app TEXT,
    username TEXT,
    group_list TEXT,
    dataset TEXT,
    params TEXT,
    made_at JULIAN,
    took_ms INTEGER
);

CREATE INDEX request_made_at_idx on request (made_at);
