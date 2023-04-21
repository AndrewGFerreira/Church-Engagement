WITH dataset
AS (SELECT DISTINCT
           p.Id,
           d.LCWeekStartDate,
           IIF(g.CampusId = 30, 1, 0) IsLCO
    FROM RMS.dbo.Attendance AS a
        INNER JOIN LCDW.Dimension.Date AS d
            ON d.FullDate = CAST(a.StartDateTime AS DATE)
               AND a.DidAttend = 1
        INNER JOIN RMS.dbo.PersonAlias AS pa
            ON pa.Id = a.PersonAliasId
        INNER JOIN RMS.dbo.Person AS p
            ON p.Id = pa.PersonId
        INNER JOIN RMS.dbo.AttendanceOccurrence AS ao
            ON ao.Id = a.OccurrenceId
        INNER JOIN RMS.dbo.[Group] AS g
            ON g.Id = ao.GroupId),
     calculate_consecutive_weeks
AS (SELECT *,
           DATEDIFF(WEEK, LAG(dataset.LCWeekStartDate) OVER (PARTITION BY Id ORDER BY LCWeekStartDate), LCWeekStartDate) AS weeksSinceLastTime
    FROM dataset),
     statusChange
AS (SELECT *,
           IIF(LAG(weeksSinceLastTime) OVER (PARTITION BY Id ORDER BY LCWeekStartDate) = weeksSinceLastTime, 0, 1) AS changeFlag
    FROM calculate_consecutive_weeks),
     chageTracking
AS (SELECT *,
           SUM(changeFlag) OVER (PARTITION BY Id ORDER BY LCWeekStartDate) AS changesTracked
    FROM statusChange),
     finalDataset
AS (SELECT *,
           ROW_NUMBER() OVER (PARTITION BY Id, changesTracked ORDER BY LCWeekStartDate) AS consecutiveWeeks
    FROM chageTracking),
     highestStreakSet
AS (SELECT Id,
           MAX(consecutiveWeeks) AS highestStreak
    FROM finalDataset
    GROUP BY Id),
     highestStreakSetAtWeek
AS (SELECT final.Id,
           final.LCWeekStartDate,
           final.changesTracked
    FROM highestStreakSet AS hs
        INNER JOIN finalDataset AS final
            ON final.Id = hs.Id
               AND final.consecutiveWeeks = hs.highestStreak),
     streak
AS (SELECT highestStreakSetAtWeek.Id,
           MAX(consecutiveWeeks) AS highestStreak,
           CAST(SUM(IsLCO) / CAST(COUNT(*) AS DECIMAL(19, 2)) * 100 AS DECIMAL(19, 2)) LCOPercentage
    FROM highestStreakSetAtWeek
        INNER JOIN finalDataset
            ON finalDataset.Id = highestStreakSetAtWeek.Id
               AND finalDataset.changesTracked = highestStreakSetAtWeek.changesTracked
    GROUP BY highestStreakSetAtWeek.Id),
     NewAccountsTotal
AS (SELECT CAST(CONCAT(YEAR(p.CreatedDateTime), '-', MONTH(p.CreatedDateTime), '-01') AS DATE) Mo,
           COUNT(Id) AS NewAccounts
    FROM RMS.dbo.Person AS p
    WHERE p.ForeignId IS NULL -- not imported
    GROUP BY CAST(CONCAT(YEAR(p.CreatedDateTime), '-', MONTH(p.CreatedDateTime), '-01') AS DATE)),
     TotalAccounts
AS (SELECT Mo,
           NewAccounts,
           SUM(NewAccounts) OVER (ORDER BY Mo) AS TotalAccounts
    FROM NewAccountsTotal),
     PersonEvents
AS (SELECT DISTINCT
           a.PersonAliasId,
           TRY_CAST(CONCAT(YEAR(a.StartDateTime), '-', MONTH(a.StartDateTime), '-01') AS DATE) AS EventMonth,
           DATEADD(WEEK, DATEDIFF(WEEK, 6, a.StartDateTime), 5) AS WeekNumber
    FROM RMS.dbo.Attendance AS a
    WHERE a.DidAttend = 1
    UNION ALL
    SELECT DISTINCT
           ft.AuthorizedPersonAliasId AS PersonAliasId,
           TRY_CAST(CONCAT(YEAR(ft.CreatedDateTime), '-', MONTH(ft.CreatedDateTime), '-01') AS DATE) AS EventMonth,
           DATEADD(WEEK, DATEDIFF(WEEK, 6, ft.CreatedDateTime), 5) AS WeekNumber
    FROM RMS.dbo.FinancialTransaction AS ft),
     PersonEventsSummary
AS (SELECT EventMonth,
           COUNT(DISTINCT PersonAliasId) ActiveUsers
    FROM PersonEvents
    GROUP BY EventMonth),
     PersonEventsSummaryWeekly
AS (SELECT EventMonth,
           WeekNumber,
           COUNT(DISTINCT PersonEvents.PersonAliasId) ActiverUsers
    FROM PersonEvents
    GROUP BY EventMonth,
             WeekNumber),
     Accounts
AS (SELECT ta.*,
           pe.ActiveUsers AS ActiveUsersMonth,
           pweek.WeekNumber,
           pweek.ActiverUsers AS ActiveUsersWeek
    FROM TotalAccounts AS ta
        LEFT JOIN PersonEventsSummary AS pe
            ON pe.EventMonth = ta.Mo
        LEFT JOIN PersonEventsSummaryWeekly AS pweek
            ON pweek.EventMonth = ta.Mo),
     PersonAttendance
AS (SELECT p.Id,
           MIN(a.StartDateTime) AS FirstAttendance,
           MAX(a.StartDateTime) AS LastAttendance,
           COUNT(*) TotalCheckIns
    FROM RMS.dbo.Attendance AS a
        INNER JOIN RMS.dbo.Person AS p
            ON RMS.dbo.ufnUtility_GetPrimaryPersonAliasId(p.Id) = a.PersonAliasId
               AND a.DidAttend = 1
    GROUP BY p.Id),
     FirstAttendance
AS (SELECT CAST(CONCAT(YEAR(p.FirstAttendance), '-', MONTH(p.FirstAttendance), '-01') AS DATE) Mo,
           COUNT(*) TotalNewCheckIns
    FROM PersonAttendance AS p
    GROUP BY CAST(CONCAT(YEAR(p.FirstAttendance), '-', MONTH(p.FirstAttendance), '-01') AS DATE)),
     LastAttendance
AS (SELECT CAST(CONCAT(YEAR(p.LastAttendance), '-', MONTH(p.LastAttendance), '-01') AS DATE) Mo,
           COUNT(*) TotalLastCheckIns
    FROM PersonAttendance AS p
    GROUP BY CAST(CONCAT(YEAR(p.LastAttendance), '-', MONTH(p.LastAttendance), '-01') AS DATE)),
     AccountStats
AS (SELECT acc.Mo,
           acc.NewAccounts,
           acc.TotalAccounts,
           fa.TotalNewCheckIns,
           la.TotalLastCheckIns,
           acc.ActiveUsersMonth,
           acc.WeekNumber,
           acc.ActiveUsersWeek
    FROM Accounts AS acc
        LEFT JOIN FirstAttendance AS fa
            ON fa.Mo = acc.Mo
        LEFT JOIN LastAttendance AS la
            ON la.Mo = acc.Mo
    WHERE la.TotalLastCheckIns <= DATEADD(MONTH, -2, GETDATE()))
SELECT piv.*
FROM AccountStats
    UNPIVOT
    (
        Numnber
        FOR NumberType IN (NewAccounts, TotalAccounts, TotalNewCheckIns, TotalLastCheckIns)
    ) piv;