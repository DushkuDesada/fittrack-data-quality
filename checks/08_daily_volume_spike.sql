-- name: No day has more than double the usual access volume
-- severity: warn
-- why: A sudden spike usually means a bulk replay or a duplicate load, which inflates daily visit reports.
-- Compares each local day per branch with the average of the 7 days before and after it.
WITH daily AS (
  SELECT e.branch_id,
         (e.event_ts AT TIME ZONE b.timezone)::date AS local_day,
         count(*) AS events
  FROM events e
  JOIN branches b ON b.branch_id = e.branch_id
  WHERE e.device_id IS NOT NULL
  GROUP BY 1, 2
), compared AS (
  SELECT d.*,
         (SELECT avg(o.events) FROM daily o
          WHERE o.branch_id = d.branch_id
            AND o.local_day BETWEEN d.local_day - 7 AND d.local_day + 7
            AND o.local_day <> d.local_day) AS usual
  FROM daily d
)
SELECT branch_id, local_day, events, round(usual) AS usual_events,
       round(events / usual, 1) AS ratio
FROM compared
WHERE usual >= 20              -- ignore tiny samples (e.g. a branch's first days)
  AND events > 2 * usual;
