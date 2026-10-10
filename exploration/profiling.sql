-- =============================================================================
-- exploration/profiling.sql
-- Initial exploration of the FitTrack database
--
-- Before starting with test cases and reports, I wanted to understand
-- what data we have, how much of it there is, and whether it matches
-- the information provided in the README.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. UNDERSTANDING THE DATA
-- First, I checked the number of records in each table and the date range
-- covered by the events.
-- -----------------------------------------------------------------------------

-- 1.1 How many records do we have in each table?

SELECT 'branches' AS tbl, count(*) FROM branches
UNION ALL SELECT 'devices', count(*) FROM devices
UNION ALL SELECT 'members', count(*) FROM members
UNION ALL SELECT 'events',  count(*) FROM events;

-- Results:
-- branches: 8
-- devices: 24
-- members: 1,122
-- events: 156,040
--
-- Observations:
-- We have 8 branches and 24 devices, which means 3 devices per branch.
-- This matches the README, where each branch should have an entrance,
-- exit, and front desk device.
--
-- The events table is much larger than the others, with over 156k records.
-- That's roughly 140 events per member.
--
-- Since most of the data is in this table, I'll probably spend most of
-- my testing and validation effort here.
--
-- Next, I wanted to check the date range of these events.


-- 1.2 What period does the data cover?

SELECT CASE WHEN device_id IS NULL THEN 'crm' ELSE 'device' END AS source,
       min(event_ts), max(event_ts), count(*)
FROM events
GROUP BY 1;

-- Results (UTC):
-- CRM:    2021-01-01 21:16 to 2024-12-31 14:54 | 1,691 events
-- Device: 2024-01-01 10:04 to 2025-01-01 06:54 | 154,349 events
--
-- Observations:
-- CRM events start in 2021, which matches the README.
--
-- One thing that caught my attention was that device events go into
-- January 1, 2025, even though the README says they cover 2024.
--
-- At first, I thought this might be a data issue, but after checking
-- the timezone difference, it makes sense.
--
-- For example:
-- 2025-01-01 06:54 UTC is actually December 31, 2024, at 22:54
-- in Los Angeles.
--
-- So the event still belongs to 2024 in the branch's local timezone.
-- It's also before the branch's closing time of 23:00.
--
-- I also checked the first device event:
-- 2024-01-01 10:04 UTC = 05:04 in New York.
--
-- Since the branch opens at 05:00, this looks reasonable.
--
-- Important for reporting:
-- I'll use each branch's local timezone when filtering events by date,
-- as mentioned in rule 5 of the README.
--
-- For example:
-- (event_ts AT TIME ZONE branches.timezone) >= '2024-01-01'
--
-- Filtering only by UTC could cause us to miss some visits,
-- especially around New Year's Eve for branches on the West Coast.
--
-- Next, I'll look at the actual values stored in the columns
-- to better understand the data and identify anything unusual.
