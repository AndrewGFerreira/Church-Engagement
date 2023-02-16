SET DATEFIRST 6 ; -- The first message starts on Saturday

-- Getting the number of new and total accounts
DROP TABLE IF EXISTS #Accounts;
WITH NewAccountsTotal AS (
SELECT CAST(CONCAT(YEAR(p.CreatedDateTime), '-' ,MONTH(p.CreatedDateTime), '-01') AS DATE) Mo, COUNT(Id) AS NewAccounts
FROM RMS.dbo.Person as p
GROUP BY CAST(CONCAT(YEAR(p.CreatedDateTime), '-' ,MONTH(p.CreatedDateTime), '-01') AS DATE)
)
SELECT Mo,
       NewAccounts,
	   SUM(NewAccounts) OVER (ORDER BY Mo) AS TotalAccounts
INTO #Accounts
FROM NewAccountsTotal
ORDER BY Mo ASC


--Getting first and last attendance for everyone who has attendance
DROP TABLE IF EXISTS #PersonAttendance;
SELECT p.Id, MIN(a.StartDateTime) AS FirstAttendance, MAX(a.StartDateTime) AS LastAttendance, COUNT(*) TotalCheckIns
INTO #PersonAttendance
FROM RMS.dbo.Attendance AS a
INNER JOIN RMS.dbo.Person AS p
	ON RMS.dbo.ufnUtility_GetPrimaryPersonAliasId(p.Id) = a.PersonAliasId
	AND a.DidAttend = 1
GROUP BY p.Id

--New accounts vs losing accounts
DROP TABLE IF EXISTS #AccountStats;
WITH FirstAttendance AS (
SELECT CAST(CONCAT(YEAR(p.FirstAttendance), '-' ,MONTH(p.FirstAttendance), '-01') AS DATE) Mo, COUNT(*) TotalNewCheckIns
FROM #PersonAttendance AS p
GROUP BY CAST(CONCAT(YEAR(p.FirstAttendance), '-' ,MONTH(p.FirstAttendance), '-01') AS DATE)
)
, LastAttendance AS (
SELECT CAST(CONCAT(YEAR(p.LastAttendance), '-' ,MONTH(p.LastAttendance), '-01') AS DATE) Mo, COUNT(*) TotalLastCheckIns
FROM #PersonAttendance AS p
GROUP BY CAST(CONCAT(YEAR(p.LastAttendance), '-' ,MONTH(p.LastAttendance), '-01') AS DATE)
)
SELECT acc.Mo, acc.NewAccounts, acc.TotalAccounts, fa.TotalNewCheckIns, la.TotalLastCheckIns
INTO #AccountStats
FROM #Accounts AS acc
LEFT JOIN FirstAttendance AS fa
	ON fa.Mo = acc.Mo
LEFT JOIN LastAttendance AS la
	ON la.Mo = acc.Mo
WHERE la.TotalLastCheckIns <= DATEADD(MONTH, -2, GETDATE())
ORDER BY fa.mo DESC

-- Get number of people in household
DROP TABLE IF EXISTS #PeopleInFamily
SELECT pa.Id, COUNT(DISTINCT gm.PersonId) AS PeopleInFamily
INTO #PeopleInFamily
FROM #PersonAttendance AS pa
INNER JOIN RMS.dbo.Person AS p
	ON p.Id = pa.Id
INNER JOIN RMS.dbo.[Group] AS g
	ON g.Id = p.PrimaryFamilyId
INNER JOIN RMS.dbo.GroupMember AS gm
	ON gm.GroupId = g.Id
GROUP BY pa.Id

-- get giving information
DROP TABLE IF EXISTS #PersonGiving
SELECT pa.Id, COUNT(ft.Id) AS NumberOfTransactions, MIN(ft.CreatedDateTime) AS FirstGift, MAX(ft.CreatedDateTime) AS LastGift
INTO #PersonGiving
FROM #PersonAttendance AS pa
INNER JOIN RMS.dbo.FinancialTransaction AS ft
	ON ft.AuthorizedPersonAliasId = RMS.dbo.ufnUtility_GetPrimaryPersonAliasId(pa.Id)
GROUP BY pa.Id

--getting the list of serving group that each person is in
DROP TABLE IF EXISTS #ServingGroupCount
SELECT pa.Id, COUNT(DISTINCT g.Id) AS ServingGroups
INTO #ServingGroupCount
FROM #PersonAttendance AS pa
INNER JOIN RMS.dbo.GroupMember AS gm
	ON gm.PersonId = pa.Id
INNER JOIN rms.dbo.[Group] AS g
	ON g.Id = gm.GroupId
INNER JOIN RMS.dbo.GroupType AS gt
	ON gt.Id = g.GroupTypeId
	AND gt.GroupTypePurposeValueId = 184 --serving
GROUP BY pa.Id

-- get count of small groups
DROP TABLE IF EXISTS #SmallGroupCount
SELECT pa.Id, COUNT(DISTINCT g.Id) SmallGroupCount
INTO #SmallGroupCount
FROM #PersonAttendance AS pa
INNER JOIN RMS.dbo.GroupMember AS gm
	ON gm.PersonId = pa.Id
INNER JOIN RMS.dbo.[Group] AS g
	ON g.Id = gm.GroupId
INNER JOIN RMS.dbo.GroupType AS gt
	ON gt.Id = g.GroupTypeId
	AND gt.GroupTypePurposeValueId = 157176-- Small Group
GROUP BY pa.Id

--get list of main next steps taken
DROP TABLE IF EXISTS #NextStepsTaken;
WITH nextstepsCTE AS (
SELECT pAttendance.Id, co.id AS ConnectionOpportunity, COUNT(cr.Id) NextStepCount
FROM rms.dbo.ConnectionRequest AS cr
INNER JOIN rms.dbo.PersonAlias AS pa
	ON pa.Id = cr.PersonAliasId
INNER JOIN #PersonAttendance AS pAttendance
	ON pAttendance.Id = pa.PersonId
INNER JOIN RMS.dbo.ConnectionOpportunity AS co
	ON co.Id = cr.ConnectionOpportunityId
	AND co.Id IN (
		4, --3 Month Tithe Challenge
		11, --Commit to Christ
		13, --I'm New
		24, --Prayer Request
		25, --Renewing Commitment to Christ
		26, --Serving Interest
		7 --Baptism Sign Up
		)
GROUP BY pAttendance.Id,
         co.id
)
SELECT *
INTO #NextStepsTaken
FROM nextstepsCTE
PIVOT (
MAX(NextStepCount)
FOR ConnectionOpportunity IN (
		[4], --3 Month Tithe Challenge
		[11], --Commit to Christ
		[13], --I'm New
		[24], --Prayer Request
		[25], --Renewing Commitment to Christ
		[26], --Serving Interest
		[7] --Baptism Sign Up
		)
) AS final


--Get final dataset #ExperimentNo1
DROP TABLE IF EXISTS ExperimentNo1
SELECT
	pa.Id,
	pa.TotalCheckIns, 
	MONTH(pa.FirstAttendance) MonthFirstAttendance,
	MONTH(pa.LastAttendance) MonthLastAttendance,
	pa.LastAttendance,
	pa.FirstAttendance,
	DATEDIFF(MONTH, pa.FirstAttendance, pa.LastAttendance) MonthsBetweenFirstAndLastAttendance, 
	p.Gender, YEAR(GETDATE()) - p.BirthYear AS Age, 
	p.MaritalStatusValueId, 
	p.AgeClassification,
	pf.PeopleInFamily,
	pg.NumberOfTransactions,
	DATEDIFF(MONTH, pg.FirstGift, pg.LastGift) AS MonthsBetweenFirstAndLastGiving,
	sg.ServingGroups,
    ns.[4] AS [3MonthTitheChallenge],
    ns.[11] AS [CommitToChrist],
    ns.[13] AS [IAnNew],
    ns.[24] AS [PrayerRequest],
    ns.[25] AS [RenewCommitToChrist],
    ns.[26] AS [ServingInterest],
    ns.[7] AS [Baptism],
	IIF(DATEDIFF(MONTH, pa.LastAttendance, GETDATE()) > 2, 1,0) AS TwoMonthsWithoutActivity
INTO ExperimentNo1
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

SELECT DISTINCT TwoMonthsWithoutActivity
FROM ExperimentNo1