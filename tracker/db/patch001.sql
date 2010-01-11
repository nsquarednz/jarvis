-- Run with sqlite3> .read patch001.sql
ALTER TABLE request ADD COLUMN dataset_type TEXT (1);
