-- SQL Server AdventureWorks database query test
-- Generated on Tue Jun 10 15:24:37 EDT 2025

USE AdventureWorksLT;
GO

-- Get the list of tables
SELECT 
    schema_name(schema_id) as schema_name,
    name as table_name
FROM 
    sys.tables
ORDER BY 
    schema_name, table_name;
GO

-- Count number of customers
SELECT COUNT(*) AS CustomerCount FROM SalesLT.Customer;
GO

-- Show sample customer data
SELECT TOP 5 
    CustomerID, 
    FirstName, 
    LastName, 
    EmailAddress
FROM 
    SalesLT.Customer
ORDER BY 
    CustomerID;
GO
