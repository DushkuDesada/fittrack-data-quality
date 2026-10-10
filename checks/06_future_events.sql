-- name: No events dated in the future
-- severity: blocker
-- why: Future timestamps mean a broken clock or a bad load and would show up in future-dated reports.
SELECT event_id, source_ref, event_type, event_ts, ingested_at
FROM events
WHERE event_ts > now() + interval '5 minutes'
   OR ingested_at > now() + interval '5 minutes';
