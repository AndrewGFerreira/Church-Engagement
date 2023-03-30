# SQL Query Description

## Experiment 

This SQL query is designed to extract various statistics related to the attendance, giving, and engagement of members in a church. The query pulls data from multiple tables in the RMS (church management system) database to calculate various metrics for each member.

The query is structured as a series of CTEs (Common Table Expressions) that build on each other to create the final dataset. The CTEs perform the following functions:

* `NewAccountsTotal:` Calculates the number of new accounts created each month.
* `TotalAccounts:` Calculates the total number of accounts at the end of each month.
* `PersonEvents:` Gets attendance and financial transaction data for each person.
* `PersonEventsSummary:` Aggregates attendance data at the month level.
* `PersonEventsSummaryWeekly:` Aggregates attendance data at the week level.
* `#Accounts:` Combines the data from the previous CTEs into a single table.
* `#PersonAttendance:` Gets the first and last attendance dates for each person with attendance.
* `FirstAttendance:` Aggregates first attendance data at the month level.
* `LastAttendance:` Aggregates last attendance data at the month level.
* `#AccountStats:` Combines the data from #Accounts, FirstAttendance, and LastAttendance into a single table to calculate new and lost accounts each month.
* `#PeopleInFamily:` Calculates the number of people in each person's family.
* `#PersonGiving:` Calculates giving data for each person.
* `#ServingGroupCount:` Calculates the number of serving groups each person is in.
* `#SmallGroupCount:` Calculates the number of small groups each person is in.
* `nextstepsCTE:` Gets the number of times each person has taken specific next steps.
* `#NextStepsTaken:` Aggregates next step data at the person level.
* `#PersonActivation:` Gets the activation date for each person.
* `Experiment:` Combines data from all of the previous CTEs into a single table.

The final SELECT statement returns all columns from the Experiment table.