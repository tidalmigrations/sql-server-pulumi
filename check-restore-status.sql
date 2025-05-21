-- SQL Server task status check script
-- Check the status of the running restore task

-- Check the status of the restore
EXEC msdb.dbo.rds_task_status @db_name = 'AdventureWorksLT';

GO