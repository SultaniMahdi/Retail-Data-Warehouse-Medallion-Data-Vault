
-- ================================================================
-- Stored Procedure: bronze.load_bronze
-- Purpose: Load all Olist CSV files into the Bronze tables.
-- Method: Full Load (truncate existing data and reload).
-- ================================================================

-- Create the procedure if it does not exist,
-- or update its definition if it already exists.
CREATE OR ALTER PROCEDURE bronze.load_bronze

    -- Define the folder containing all CSV files.
    -- This is the default folder if no parameter is supplied.
    -- The path must end with a backslash (\).
    @base_path NVARCHAR(500) = 'C:\data\olist\'

AS
BEGIN

    -- Prevent SQL Server from returning additional
    -- "(n rows affected)" messages after SQL statements.
    SET NOCOUNT ON;


    -- ============================================================
    -- 1. DECLARE VARIABLES FOR TIME MEASUREMENT
    -- ============================================================

    -- Store the start time of the entire loading process.
    DECLARE @batch_start DATETIME2 = SYSDATETIME();

    -- Store the end time of the entire loading process.
    DECLARE @batch_end DATETIME2;

    -- Store the start time of the current table's loading process.
    DECLARE @step_start DATETIME2;

    -- Store the end time of the current table's loading process.
    DECLARE @step_end DATETIME2;


    -- ============================================================
    -- 2. DECLARE VARIABLES FOR THE LOADING PROCESS
    -- ============================================================

    -- Store the name of the current target table.
    DECLARE @table_name SYSNAME;

    -- Store the name of the current CSV file.
    DECLARE @file_name NVARCHAR(260);

    -- Store the list of columns to be loaded.
    DECLARE @cols NVARCHAR(MAX);

    -- Store dynamically generated SQL commands as text.
    DECLARE @sql NVARCHAR(MAX);

    -- Store the number of rows inserted into the target table.
    DECLARE @rows INT;

    -- Initialize the current processing step to zero.
    DECLARE @step_no INT = 0;

    -- Store the row-ending character sequence for each CSV file.
    DECLARE @row_term NVARCHAR(10);


    -- ============================================================
    -- 3. CREATE A TABLE VARIABLE WITH THE CSV FILE INFORMATION
    -- ============================================================

    -- Create a temporary working list inside this procedure.
    -- It maps each target table to its CSV file and row terminator.
    DECLARE @load_list TABLE
    (
        -- Automatically generate step numbers starting at 1.
        step_no INT IDENTITY(1,1),

        -- Store the target table name without the schema prefix.
        table_name SYSNAME,

        -- Store the CSV filename.
        file_name NVARCHAR(260),

        -- Store the row-ending character sequence.
        row_term NVARCHAR(10)
    );


    -- Insert the nine CSV-to-table mappings into the working list.
    INSERT INTO @load_list (table_name, file_name, row_term)
    VALUES
        ('orders',
         'olist_orders_dataset.csv', '0x0a'),

        ('customers',
         'olist_customers_dataset.csv', '0x0a'),

        ('geolocation',
         'olist_geolocation_dataset.csv', '0x0a'),

        ('order_items',
         'olist_order_items_dataset.csv', '0x0a'),

        ('order_payments',
         'olist_order_payments_dataset.csv', '0x0a'),

        ('order_reviews',
         'olist_order_reviews_dataset.csv', '0x0d0a'),

        ('products',
         'olist_products_dataset.csv', '0x0a'),

        ('sellers',
         'olist_sellers_dataset.csv', '0x0a'),

        ('product_category_translation',
         'product_category_name_translation.csv', '0x0a');


    -- Count how many CSV files must be processed.
    -- The result is 9 for the current list.
    DECLARE @total_steps INT =
        (SELECT COUNT(*) FROM @load_list);


    -- ============================================================
    -- 4. START ERROR HANDLING
    -- ============================================================

    -- Execute the loading process inside TRY.
    -- If a catchable SQL error occurs, control moves to CATCH.
    BEGIN TRY
        -- Display a separator in the execution messages.
        PRINT '================================================================';

        -- Display the name of the loading process.
        PRINT 'Loading Bronze Layer (Olist Brazilian E-Commerce)';

        -- Display the overall start time.
        PRINT 'Start time : '
            + CONVERT(VARCHAR(23), @batch_start, 121);

        -- Display the folder containing the CSV files.
        PRINT 'Source path: ' + @base_path;

        -- Display another separator.
        PRINT '================================================================';


        -- ========================================================
        -- 5. LOOP THROUGH ALL CSV FILES
        -- ========================================================

        -- Repeat while there are still tables to process.
        WHILE @step_no < @total_steps
        BEGIN

            -- Increase the step number by one.
            SET @step_no += 1;


            -- Retrieve the information for the current step.
            -- For step 1, this selects the orders table and CSV file.
            SELECT
                @table_name = table_name,
                @file_name  = file_name,
                @row_term   = row_term
            FROM @load_list
            WHERE step_no = @step_no;


            -- Record the start time for the current table.
            SET @step_start = SYSDATETIME();


            -- Display the current step number and target table.
            PRINT '';
            PRINT '----------------------------------------------------------------';

            PRINT '['
                + CAST(@step_no AS VARCHAR(2))
                + '/'
                + CAST(@total_steps AS VARCHAR(2))
                + '] Table: bronze.'
                + @table_name;

            -- Display the full path of the current CSV file.
            PRINT '     File : ' + @base_path + @file_name;

            -- Display the start time for the current table.
            PRINT '     Start: '
                + CONVERT(VARCHAR(23), @step_start, 121);

            PRINT '----------------------------------------------------------------';


            -- ====================================================
            -- STEP A: EMPTY THE TARGET TABLE
            -- ====================================================

            -- Display which table is about to be emptied.
            PRINT '>> Step A: Truncating table bronze.' + @table_name;

            -- Build a SQL command dynamically.
            -- QUOTENAME safely delimits the table name as an identifier.
            -- Example result: TRUNCATE TABLE bronze.[orders];
            SET @sql =
                N'TRUNCATE TABLE bronze.'
                + QUOTENAME(@table_name)
                + N';';

            -- Execute the dynamically generated TRUNCATE command.
            EXEC sys.sp_executesql @sql;


            -- ====================================================
            -- STEP B: RETRIEVE THE COLUMN LIST
            -- ====================================================

            -- Display a status message.
            PRINT '>> Step B: Reading CSV column list from metadata';

            -- Read the target table's column names from SQL Server metadata.
            -- Exclude load_date and record_source because their values
            -- are expected to be supplied by column DEFAULT constraints.
            -- QUOTENAME adds brackets around each column name.
            -- STRING_AGG joins the names with commas.
            -- ORDER BY column_id preserves the target table's column order.
            SELECT @cols =
                STRING_AGG(
                    CAST(QUOTENAME(c.name) AS NVARCHAR(MAX)),
                    N', '
                ) WITHIN GROUP (ORDER BY c.column_id)
            FROM sys.columns AS c
            WHERE c.object_id =
                OBJECT_ID(N'bronze.' + @table_name)
              AND c.name NOT IN
                ('load_date', 'record_source');


            -- ====================================================
            -- STEP C: LOAD THE CSV INTO A STAGING TABLE
            -- ====================================================

            -- Display a status message.
            PRINT '>> Step C: Bulk inserting data from CSV file';


            -- Build the SQL command that creates a staging table,
            -- imports the CSV, inserts the data into Bronze,
            -- captures the inserted row count and drops staging.
            SET @sql = N'

                -- Create an empty local temporary table called #stg.
                -- TOP (0) copies the selected column structure without rows.
                SELECT TOP (0) ' + @cols + N'
                INTO #stg
                FROM bronze.' + QUOTENAME(@table_name) + N';


                -- Import the CSV file into the temporary staging table.
                BULK INSERT #stg

                -- Specify the full path of the current CSV file.
                FROM ''' + @base_path + @file_name + N'''

                -- Define how SQL Server should read the CSV file.
                WITH
                (
                    -- Tell SQL Server that the input format is CSV.
                    FORMAT = ''CSV'',

                    -- Specify double quotes as the CSV field quote character.
                    FIELDQUOTE = ''"'',

                    -- Specify a comma as the field separator.
                    FIELDTERMINATOR = '','',

                    -- Specify the row-ending sequence for this file.
                    ROWTERMINATOR = ''' + @row_term + N''',

                    -- Skip the first row because it contains column headers.
                    FIRSTROW = 2,

                    -- Read the file using UTF-8 encoding.
                    CODEPAGE = ''65001'',

                    -- Request a table lock during the bulk import.
                    TABLOCK
                );


                -- Insert the staged data into the actual Bronze table.
                -- Explicitly specify the destination columns.
                INSERT INTO bronze.' + QUOTENAME(@table_name) + N'
                    (' + @cols + N')

                -- Select the matching columns from the staging table.
                SELECT ' + @cols + N'
                FROM #stg;


                -- Capture the number of rows inserted by the INSERT.
                -- This must be executed immediately after the INSERT.
                SET @rows_out = @@ROWCOUNT;


                -- Delete the temporary staging table after loading.
                DROP TABLE #stg;
            ';


            -- Execute the dynamically generated loading commands.
            -- Declare @rows_out as an output parameter inside the
            -- dynamic SQL and return its value to the outer variable @rows.
            EXEC sys.sp_executesql
                @sql,
                N'@rows_out INT OUTPUT',
                @rows_out = @rows OUTPUT;


            -- ====================================================
            -- STEP D: DISPLAY THE LOADING RESULT
            -- ====================================================

            -- Record the end time for the current table.
            SET @step_end = SYSDATETIME();

            -- Display a success message for this step.
            PRINT '>> Step D: Load finished';

            -- Display the number of rows inserted.
            -- N0 formats the number without decimal places.
            PRINT '     Rows loaded: '
                + FORMAT(@rows, 'N0');

            -- Display the end time.
            PRINT '     End        : '
                + CONVERT(VARCHAR(23), @step_end, 121);

            -- Calculate the duration in milliseconds,
            -- divide by 1000.0 to obtain seconds,
            -- and convert the result to text.
            PRINT '     Duration   : '
                + CAST(
                    DATEDIFF(
                        MILLISECOND,
                        @step_start,
                        @step_end
                    ) / 1000.0 AS VARCHAR(20)
                )
                + ' seconds';

        END; -- End of the WHILE loop.


        -- ========================================================
        -- 6. DISPLAY THE OVERALL RESULT
        -- ========================================================

        -- Record the end time of the entire loading process.
        SET @batch_end = SYSDATETIME();

        -- Display the overall success message.
        PRINT '';
        PRINT '================================================================';
        PRINT 'Bronze layer load completed successfully';

        -- Display the overall end time.
        PRINT 'End time      : '
            + CONVERT(VARCHAR(23), @batch_end, 121);

        -- Calculate and display the total duration in seconds.
        PRINT 'Total duration: '
            + CAST(
                DATEDIFF(
                    MILLISECOND,
                    @batch_start,
                    @batch_end
                ) / 1000.0 AS VARCHAR(20)
            )
            + ' seconds';

        PRINT '================================================================';

    END TRY


    -- ============================================================
    -- 7. HANDLE ERRORS
    -- ============================================================

    BEGIN CATCH

        -- Display a blank line and an error separator.
        PRINT '';
        PRINT '================================================================';

        -- Display the table being processed when the error occurred.
        PRINT 'ERROR while loading bronze.'
            + ISNULL(@table_name, '?');

        -- Display the SQL Server error message.
        PRINT 'Message : ' + ERROR_MESSAGE();

        -- Display the SQL Server error number.
        PRINT 'Number  : '
            + CAST(ERROR_NUMBER() AS VARCHAR(10));

        -- Display the line number associated with the error.
        PRINT 'Line    : '
            + CAST(ERROR_LINE() AS VARCHAR(10));

        -- Display the time when the error was reported.
        PRINT 'Time    : '
            + CONVERT(VARCHAR(23), SYSDATETIME(), 121);

        PRINT '================================================================';

        -- Rethrow the original error so that calling systems,
        -- such as SQL Server Agent or Airflow, can detect the failure.
        THROW;

    END CATCH;

END;
GO


-- ================================================================
-- 8. EXECUTE THE STORED PROCEDURE
-- ================================================================

-- Start the full load using the folder containing your CSV files.
--EXEC bronze.load_bronze
    --@base_path = 'C:\Users\mahdi\Downloads\archive\';
