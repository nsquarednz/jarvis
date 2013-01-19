CREATE OR REPLACE FUNCTION julian(t timestamp)
RETURNS double precision AS $$
SELECT extract(epoch from $1) / (60 * 60 * 24.0) + 2440587.5;
$$ LANGUAGE SQL;

COMMENT ON FUNCTION julian(timestamp) IS 'convert timestamp to julian format (days since 4713-01-01 12:00:00 BC)';
