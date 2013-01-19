-- truncate to nearest interval (must be a multiple of 1 second)
-- Note: EXTRACT(EPOCH FROM 'epoch'::timestamp) returns negative timezone offset
CREATE FUNCTION date_trunc_interval(interval, timestamp)
RETURNS timestamp AS $$
    SELECT
        'epoch'::timestamp + (
            trunc(EXTRACT(EPOCH FROM $2) / EXTRACT(EPOCH FROM $1)) * EXTRACT(EPOCH FROM $1)
            - EXTRACT(EPOCH FROM 'epoch'::timestamp)
        ) * '1 second'::interval;
$$ LANGUAGE SQL;

