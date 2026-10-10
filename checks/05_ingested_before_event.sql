-- name: No event reaches the database before it happened
-- severity: blocker
-- why: event_ts after ingested_at means the sender's clock is wrong, so visits land on the wrong day or hour.
-- Edge case: a few seconds of difference between clocks is normal, so 1 minute is tolerated.
SELECT coalesce(device_id, 'crm')        AS sender,
       count(*)                          AS rows,
       min(event_ts - ingested_at)       AS min_ahead,
       max(event_ts - ingested_at)       AS max_ahead,
       min(ingested_at)::date            AS first_day,
       max(ingested_at)::date            AS last_day
FROM events
WHERE event_ts > ingested_at + interval '1 minute'
GROUP BY 1;
