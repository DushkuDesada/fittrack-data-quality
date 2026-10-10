-- name: No device events are missing (no gaps in device sequence numbers)
-- severity: warn
-- why: source_ref = <device_id>:<sequence>; a jump in the sequence means events the device produced never reached the database (lost visits or check-outs).
-- Edge cases: duplicates do not matter (distinct sequence numbers only); non-numeric
-- sequences are ignored here (check 04 validates the format against the device).
WITH seqs AS (
  SELECT device_id,
         split_part(source_ref, ':', 2)::bigint AS seq,
         min(event_ts)                          AS event_ts
  FROM events
  WHERE device_id IS NOT NULL
    AND split_part(source_ref, ':', 2) ~ '^[0-9]+$'
  GROUP BY 1, 2
), steps AS (
  SELECT device_id, seq, event_ts,
         lead(seq)      OVER (PARTITION BY device_id ORDER BY seq) AS next_seq,
         lead(event_ts) OVER (PARTITION BY device_id ORDER BY seq) AS next_event_ts
  FROM seqs
)
SELECT device_id,
       seq + 1          AS first_missing,
       next_seq - 1     AS last_missing,
       next_seq - seq - 1 AS missing_events,
       event_ts         AS last_seen_before_gap,
       next_event_ts    AS first_seen_after_gap
FROM steps
WHERE next_seq - seq > 1;
