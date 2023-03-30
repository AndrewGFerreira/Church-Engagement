SET DATEFIRST 6; -- The first message starts on Saturday

DROP TABLE IF EXISTS #Accounts;
WITH NewAccountsTotal
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
             WeekNumber)
SELECT ta.*,
       pe.ActiveUsers AS ActiveUsersMonth,
       pweek.WeekNumber,
       pweek.ActiverUsers AS ActiveUsersWeek
INTO #Accounts
FROM TotalAccounts AS ta
    LEFT JOIN PersonEventsSummary AS pe
        ON pe.EventMonth = ta.Mo
    LEFT JOIN PersonEventsSummaryWeekly AS pweek
        ON pweek.EventMonth = ta.Mo
ORDER BY ta.Mo ASC;


--Getting first and last attendance for everyone who has attendance
DROP TABLE IF EXISTS #PersonAttendance;
SELECT p.Id,
       MIN(a.StartDateTime) AS FirstAttendance,
       MAX(a.StartDateTime) AS LastAttendance,
       COUNT(*) TotalCheckIns
INTO #PersonAttendance
FROM RMS.dbo.Attendance AS a
    INNER JOIN RMS.dbo.Person AS p
        ON RMS.dbo.ufnUtility_GetPrimaryPersonAliasId(p.Id) = a.PersonAliasId
           AND a.DidAttend = 1
GROUP BY p.Id;

--New accounts vs losing accounts
DROP TABLE IF EXISTS #AccountStats;
WITH FirstAttendance
AS (SELECT CAST(CONCAT(YEAR(p.FirstAttendance), '-', MONTH(p.FirstAttendance), '-01') AS DATE) Mo,
           COUNT(*) TotalNewCheckIns
    FROM #PersonAttendance AS p
    GROUP BY CAST(CONCAT(YEAR(p.FirstAttendance), '-', MONTH(p.FirstAttendance), '-01') AS DATE)),
     LastAttendance
AS (SELECT CAST(CONCAT(YEAR(p.LastAttendance), '-', MONTH(p.LastAttendance), '-01') AS DATE) Mo,
           COUNT(*) TotalLastCheckIns
    FROM #PersonAttendance AS p
    GROUP BY CAST(CONCAT(YEAR(p.LastAttendance), '-', MONTH(p.LastAttendance), '-01') AS DATE))
SELECT acc.Mo,
       acc.NewAccounts,
       acc.TotalAccounts,
       fa.TotalNewCheckIns,
       la.TotalLastCheckIns,
       acc.ActiveUsersMonth,
       acc.WeekNumber,
       acc.ActiveUsersWeek
INTO #AccountStats
FROM #Accounts AS acc
    LEFT JOIN FirstAttendance AS fa
        ON fa.Mo = acc.Mo
    LEFT JOIN LastAttendance AS la
        ON la.Mo = acc.Mo
WHERE la.TotalLastCheckIns <= DATEADD(MONTH, -2, GETDATE())
ORDER BY fa.Mo DESC;


-- Get number of people in household
DROP TABLE IF EXISTS #PeopleInFamily;
SELECT pa.Id,
       COUNT(DISTINCT gm.PersonId) AS PeopleInFamily
INTO #PeopleInFamily
FROM #PersonAttendance AS pa
    INNER JOIN RMS.dbo.Person AS p
        ON p.Id = pa.Id
    INNER JOIN RMS.dbo.[Group] AS g
        ON g.Id = p.PrimaryFamilyId
    INNER JOIN RMS.dbo.GroupMember AS gm
        ON gm.GroupId = g.Id
GROUP BY pa.Id;

-- get giving information
DROP TABLE IF EXISTS #PersonGiving;
SELECT pa.Id,
       COUNT(ft.Id) AS NumberOfTransactions,
       MIN(ft.CreatedDateTime) AS FirstGift,
       MAX(ft.CreatedDateTime) AS LastGift
INTO #PersonGiving
FROM #PersonAttendance AS pa
    INNER JOIN RMS.dbo.FinancialTransaction AS ft
        ON ft.AuthorizedPersonAliasId = RMS.dbo.ufnUtility_GetPrimaryPersonAliasId(pa.Id)
GROUP BY pa.Id;

--getting the list of serving group that each person is in
DROP TABLE IF EXISTS #ServingGroupCount;
SELECT pa.Id,
       COUNT(DISTINCT g.Id) AS ServingGroups
INTO #ServingGroupCount
FROM #PersonAttendance AS pa
    INNER JOIN RMS.dbo.GroupMember AS gm
        ON gm.PersonId = pa.Id
    INNER JOIN RMS.dbo.[Group] AS g
        ON g.Id = gm.GroupId
    INNER JOIN RMS.dbo.GroupType AS gt
        ON gt.Id = g.GroupTypeId
           AND gt.GroupTypePurposeValueId = 184 --serving
GROUP BY pa.Id;

-- get count of small groups
DROP TABLE IF EXISTS #SmallGroupCount;
SELECT pa.Id,
       COUNT(DISTINCT g.Id) SmallGroupCount
INTO #SmallGroupCount
FROM #PersonAttendance AS pa
    INNER JOIN RMS.dbo.GroupMember AS gm
        ON gm.PersonId = pa.Id
    INNER JOIN RMS.dbo.[Group] AS g
        ON g.Id = gm.GroupId
    INNER JOIN RMS.dbo.GroupType AS gt
        ON gt.Id = g.GroupTypeId
           AND gt.GroupTypePurposeValueId = 157176 -- Small Group
GROUP BY pa.Id;

--get list of main next steps taken
DROP TABLE IF EXISTS #NextStepsTaken;
WITH nextstepsCTE
AS (SELECT pAttendance.Id,
           co.Id AS ConnectionOpportunity,
           COUNT(cr.Id) NextStepCount
    FROM RMS.dbo.ConnectionRequest AS cr
        INNER JOIN RMS.dbo.PersonAlias AS pa
            ON pa.Id = cr.PersonAliasId
        INNER JOIN #PersonAttendance AS pAttendance
            ON pAttendance.Id = pa.PersonId
        INNER JOIN RMS.dbo.ConnectionOpportunity AS co
            ON co.Id = cr.ConnectionOpportunityId
               AND co.Id IN (   4,  --3 Month Tithe Challenge
                                11, --Commit to Christ
                                13, --I'm New
                                24, --Prayer Request
                                25, --Renewing Commitment to Christ
                                26, --Serving Interest
                                7   --Baptism Sign Up
                            )
    GROUP BY pAttendance.Id,
             co.Id)
SELECT *
INTO #NextStepsTaken
FROM nextstepsCTE
    PIVOT
    (
        MAX(NextStepCount)
        FOR ConnectionOpportunity IN (   [4],  --3 Month Tithe Challenge
                                         [11], --Commit to Christ
                                         [13], --I'm New
                                         [24], --Prayer Request
                                         [25], --Renewing Commitment to Christ
                                         [26], --Serving Interest
                                         [7]   --Baptism Sign Up
                                     )
    ) AS final;

--activation event
DROP TABLE IF EXISTS #PersonActivation;
SELECT p.Id,
       p.CreatedDateTime,
       pa.FirstAttendance,
       pg.FirstGift,
       CASE
           WHEN pa.FirstAttendance < pg.FirstGift THEN
               pa.FirstAttendance
           WHEN pg.FirstGift < pa.FirstAttendance THEN
               pg.FirstGift
           WHEN pg.FirstGift = pa.FirstAttendance THEN
               pa.FirstAttendance
           ELSE
               NULL
       END AS ActivationDate
INTO #PersonActivation
FROM RMS.dbo.Person AS p
    LEFT JOIN #PersonAttendance AS pa
        ON pa.Id = p.Id
    LEFT JOIN #PersonGiving AS pg
        ON pg.Id = p.Id;


--Get final dataset
DROP TABLE IF EXISTS Experiment;
SELECT pa.Id,
       p.RecordTypeValueId AS PersonType,
       ISNULL(pa.TotalCheckIns, 0) AS TotalCheckIns,
       CAST(pactivation.ActivationDate AS DATE) AS ActivationDate,
       DATEDIFF(DAY, CAST(p.CreatedDateTime AS DATE), CAST(pactivation.ActivationDate AS DATE)) AS TimeToActivate,
       IIF(p.ForeignId IS NULL, 0, 1) IsImported,
       CAST(p.CreatedDateTime AS DATE) PersonCreatedDate,
       CAST(pa.FirstAttendance AS DATE) AS FirstAttendanceDate,
       DATEDIFF(DAY, p.CreatedDateTime, pa.FirstAttendance) AS DaysToFirstAttendance,
       MONTH(pa.FirstAttendance) MonthFirstAttendance,
       MONTH(pa.LastAttendance) MonthLastAttendance,
       pa.LastAttendance,
       pa.FirstAttendance,
       DATEDIFF(MONTH, pa.FirstAttendance, pa.LastAttendance) MonthsBetweenFirstAndLastAttendance,
       ISNULL(p.Gender, 0) AS Gender,
       YEAR(GETDATE()) - p.BirthYear AS Age,
       ISNULL(p.MaritalStatusValueId, 675) AS MaritalStatusValueId,
       p.AgeClassification,
       ISNULL(pf.PeopleInFamily, 0) AS PeopleInFamily,
       pg.NumberOfTransactions,
       pg.FirstGift,
       pg.LastGift,
       ISNULL(DATEDIFF(MONTH, pg.FirstGift, pg.LastGift), 0) AS MonthsBetweenFirstAndLastGiving,
       sg.ServingGroups,
       ISNULL(ns.[4], 0) AS [3MonthTitheChallenge],
       ISNULL(ns.[11], 0) AS [CommitToChrist],
       ISNULL(ns.[13], 0) AS [IAnNew],
       ISNULL(ns.[24], 0) AS [PrayerRequest],
       ISNULL(ns.[25], 0) AS [RenewCommitToChrist],
       ISNULL(ns.[26], 0) AS [ServingInterest],
       ISNULL(ns.[7], 0) AS [Baptism],
       ISNULL(st.highestStreak, 0) AS highestStreak,
       ISNULL(st.LCOPercentage, 0) AS LCOPercentage,
       IIF(DATEDIFF(MONTH, pa.LastAttendance, GETDATE()) > 2, 1, 0) AS TwoMonthsWithoutActivity
INTO Experiment
FROM #PersonAttendance AS pa
    INNER JOIN RMS.dbo.Person AS p
        ON p.Id = pa.Id
    LEFT JOIN #PeopleInFamily AS pf
        ON pa.Id = pf.Id
    LEFT JOIN #PersonGiving AS pg
        ON pa.Id = pg.Id
    LEFT JOIN #ServingGroupCount AS sg
        ON sg.Id = p.Id
    LEFT JOIN #NextStepsTaken AS ns
        ON ns.Id = p.Id
    LEFT JOIN #PersonActivation AS pactivation
        ON pactivation.Id = pa.Id;


SELECT *
FROM Experiment;