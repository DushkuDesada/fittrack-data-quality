-- name: members.status and membership_tier agree with the event history
-- severity: warn
-- why: Rule 1 says state comes from events. If anyone reports from the members snapshot instead, active counts and tiers will be wrong.
WITH last_state AS (
  SELECT DISTINCT ON (member_id) member_id, lower(event_type) AS et
  FROM events
  WHERE lower(event_type) IN ('membership_started','membership_reactivated','membership_cancelled')
  ORDER BY member_id, event_ts DESC, event_id DESC
), last_tier AS (
  SELECT DISTINCT ON (member_id) member_id, coalesce(details->>'to', details->>'tier') AS tier
  FROM events
  WHERE lower(event_type) IN ('membership_started','membership_reactivated','tier_changed')
  ORDER BY member_id, event_ts DESC, event_id DESC
)
SELECT m.member_id, m.status, s.et AS last_membership_event, m.membership_tier, t.tier AS tier_from_events
FROM members m
LEFT JOIN last_state s USING (member_id)
LEFT JOIN last_tier  t USING (member_id)
WHERE s.et IS NULL
   OR m.status IS DISTINCT FROM CASE WHEN s.et = 'membership_cancelled' THEN 'cancelled' ELSE 'active' END
   OR m.membership_tier IS DISTINCT FROM t.tier;
