-- SQL Server task status check script with full details
-- Check the status of the running restore task with all columns

-- Check the status of the restore with all columns
SELECT
  *
FROM
  MSDB.DBO.RDS_TASK_STATUS
WHERE
  DATABASE_NAME = 'AdventureWorksLT'
ORDER BY
  TASK_ID DESC;

GO