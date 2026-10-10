-- name: Members bring no more friends per month than their tier allows
-- severity: warn
-- why: Rule 4 - basic 2, standard 3, premium 8 friend visits per month. Overuse means the desk does not enforce the allowance and inflates friend usage.
-- Edge cases: month and tier are taken in the branch's local time (rule 5); the tier is the
-- member's tier at the end of that month; duplicates are collapsed per source_ref;
-- members with no tier at all are reported by check 19, not here.
WITH ev AS (
  SELECT DISTINCT ON (e.source_ref)
         e.member_id, e.event_id, e.event_ts, lower(e.event_type) AS et, e.details,
         e.event_ts AT TIME ZONE coalesce(b.timezone, 'UTC') AS local_ts
  FROM events e
  LEFT JOIN branches b ON b.branch_id = e.branch_id
  ORDER BY e.source_ref, e.event_ts, e.event_id
), friend_months AS MATERIALIZED (
  SELECT member_id, date_trunc('month', local_ts) AS month, count(*) AS friend_visits
  FROM ev
  WHERE et = 'friend_visit'
  GROUP BY 1, 2
), tier_events AS MATERIALIZED (
  SELECT member_id, event_id, event_ts, local_ts, coalesce(details->>'to', details->>'tier') AS tier
  FROM ev
  WHERE et IN ('membership_started', 'membership_reactivated', 'tier_changed')
), with_tier AS (
  SELECT DISTINCT ON (fm.member_id, fm.month)
         fm.*, t.tier
  FROM friend_months fm
  LEFT JOIN tier_events t
         ON t.member_id = fm.member_id
        AND t.local_ts < fm.month + interval '1 month'
  ORDER BY fm.member_id, fm.month, t.event_ts DESC NULLS LAST, t.event_id DESC NULLS LAST
)
SELECT member_id, to_char(month, 'YYYY-MM') AS month, tier, friend_visits,
       CASE tier WHEN 'basic' THEN 2 WHEN 'standard' THEN 3 WHEN 'premium' THEN 8 END AS allowance
FROM with_tier
WHERE friend_visits > CASE tier WHEN 'basic' THEN 2 WHEN 'standard' THEN 3 WHEN 'premium' THEN 8 END;
