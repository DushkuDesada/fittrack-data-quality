-- name: Members only check in while their membership is active
-- severity: warn
-- why: Check-ins by members without an active membership point to an access-control gap or late CRM data.
WITH ev AS (
  SELECT DISTINCT ON (source_ref) member_id, branch_id, event_ts, event_id
  FROM events
  WHERE lower(event_type) = 'check_in'
  ORDER BY source_ref, event_ts, event_id
)
SELECT ev.member_id, ev.branch_id, ev.event_ts, st.et AS membership_state
FROM ev
JOIN members m ON m.member_id = ev.member_id          -- unknown members are check 03
LEFT JOIN LATERAL (
  SELECT lower(c.event_type) AS et
  FROM events c
  WHERE c.member_id = ev.member_id
    AND lower(c.event_type) IN ('membership_started','membership_reactivated','membership_cancelled')
    AND c.event_ts <= ev.event_ts
  ORDER BY c.event_ts DESC, c.event_id DESC
  LIMIT 1
) st ON true
WHERE st.et IS NULL OR st.et = 'membership_cancelled';
