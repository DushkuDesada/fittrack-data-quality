-- name: CRM events arrive within a day of happening
-- severity: warn
-- why: Late-arriving CRM events (e.g. cancellations) make month-end reports wrong when they run: active members are overstated until the late events land.
-- Edge case: device delays are covered by check 05 (clock) and are normally seconds; this check
-- is about the CRM feed only. One day of delay is tolerated.
SELECT lower(event_type)                      AS event_type,
       count(*)                               AS late_events,
       min(ingested_at - event_ts)            AS min_delay,
       max(ingested_at - event_ts)            AS max_delay,
       count(*) FILTER (WHERE date_trunc('month', ingested_at) <> date_trunc('month', event_ts))
                                              AS landed_in_a_later_month
FROM events
WHERE source_ref LIKE 'crm:%'
  AND ingested_at > event_ts + interval '1 day'
GROUP BY 1;
