-- name: Membership events follow a valid lifecycle
-- severity: blocker
-- why: Rule 1 - membership state is derived from events. An impossible order (cancel before start, tier change while cancelled) breaks active-member counts.
WITH crm AS (
  SELECT member_id, event_id, event_ts, lower(event_type) AS et, details,
         lag(lower(event_type)) OVER w AS prev_et,
         lag(coalesce(details->>'tier', details->>'to')) OVER (
             PARTITION BY member_id, lower(event_type) IN ('membership_started','membership_reactivated','tier_changed')
             ORDER BY event_ts, event_id) AS prev_tier
  FROM events
  WHERE source_ref LIKE 'crm:%'
  WINDOW w AS (PARTITION BY member_id ORDER BY event_ts, event_id)
), state AS (
  SELECT *,
         -- last lifecycle event before this one (ignores tier changes)
         (SELECT lower(p.event_type) FROM events p
          WHERE p.member_id = crm.member_id AND p.source_ref LIKE 'crm:%'
            AND lower(p.event_type) <> 'tier_changed'
            AND (p.event_ts, p.event_id) < (crm.event_ts, crm.event_id)
          ORDER BY p.event_ts DESC, p.event_id DESC LIMIT 1) AS prev_state
  FROM crm
)
SELECT member_id, event_id, event_ts, et, prev_state, details,
       CASE
         WHEN et = 'membership_started'     AND prev_state IS NOT NULL                    THEN 'started twice'
         WHEN et = 'membership_reactivated' AND prev_state IS DISTINCT FROM 'membership_cancelled' THEN 'reactivated without a cancellation'
         WHEN et = 'membership_cancelled'   AND prev_state NOT IN ('membership_started','membership_reactivated') THEN 'cancelled while not active'
         WHEN et = 'membership_cancelled'   AND prev_state IS NULL                        THEN 'cancelled before starting'
         WHEN et = 'tier_changed' AND (prev_state IS NULL OR prev_state = 'membership_cancelled') THEN 'tier changed while not active'
         WHEN et = 'tier_changed' AND details->>'from' IS DISTINCT FROM prev_tier       THEN 'tier_changed.from is not the previous tier'
         WHEN et = 'tier_changed' AND details->>'from' = details->>'to'                 THEN 'tier changed to the same tier'
       END AS problem
FROM state
WHERE (et = 'membership_started'     AND prev_state IS NOT NULL)
   OR (et = 'membership_reactivated' AND prev_state IS DISTINCT FROM 'membership_cancelled')
   OR (et = 'membership_cancelled'   AND (prev_state IS NULL OR prev_state NOT IN ('membership_started','membership_reactivated')))
   OR (et = 'tier_changed' AND (prev_state IS NULL OR prev_state = 'membership_cancelled'
                                OR details->>'from' IS DISTINCT FROM prev_tier
                                OR details->>'from' = details->>'to'));
