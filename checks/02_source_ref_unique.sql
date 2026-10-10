-- name: source_ref identifies exactly one event
-- severity: blocker
-- why: Retries and replays create copies of the same event and inflate visit counts.
SELECT source_ref,
       count(*)                            AS copies,
       count(DISTINCT event_ts)            AS distinct_event_ts,
       min(event_ts)                       AS first_event_ts,
       max(event_ts)                       AS last_event_ts
FROM events
GROUP BY source_ref
HAVING count(*) > 1;
