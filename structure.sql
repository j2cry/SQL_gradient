CREATE SCHEMA GRADIENT

----------------------------------------
CREATE OR ALTER PROCEDURE [GRADIENT].[init]
AS
BEGIN
    DECLARE @QUERY VARCHAR(MAX)
    DECLARE @XSIZE INT = (SELECT COUNT(*) FROM [INFORMATION_SCHEMA].[COLUMNS] WHERE [TABLE_SCHEMA] = 'GRADIENT' AND [TABLE_NAME] = 'X' AND ISNUMERIC([COLUMN_NAME]) = 1)
    -- init batch
    DROP TABLE IF EXISTS [GRADIENT].[Xb]
    SELECT * INTO [GRADIENT].[Xb] FROM [GRADIENT].[X]
    ALTER TABLE [GRADIENT].[Xb] ADD [0] DECIMAL(19,6) NOT NULL DEFAULT 1
    -- init weights table
    DROP TABLE IF EXISTS [GRADIENT].[W]
    SELECT TOP 0 * INTO [GRADIENT].[W] FROM [GRADIENT].[Y]
    -- init weights
    DECLARE @COUNTER INT = 0
    WHILE @COUNTER <= @XSIZE
    BEGIN
        SET @QUERY = 'INSERT INTO [GRADIENT].[W] VALUES (' + CAST(@COUNTER AS VARCHAR(MAX)) + (SELECT ', RAND()' FROM [INFORMATION_SCHEMA].[COLUMNS] WHERE [TABLE_SCHEMA] = 'GRADIENT' AND [TABLE_NAME] = 'Y' AND [DATA_TYPE] = 'DECIMAL' FOR XML PATH('')) + ')'
        EXEC(@QUERY)
        SET @COUNTER = @COUNTER + 1
    END
END


----------------------------------------
CREATE OR ALTER PROCEDURE [GRADIENT].[flat]
    @TBSCHEMA VARCHAR(MAX),
    @TBNAME VARCHAR(MAX)
AS
BEGIN
    DECLARE @QUERY VARCHAR(MAX) = STUFF((SELECT ' UNION ALL SELECT [idx], ' + [COLUMN_NAME] + ' [col], '+ QUOTENAME([COLUMN_NAME]) + '[value] FROM ' + QUOTENAME(@TBSCHEMA) + '.' + QUOTENAME(@TBNAME)
        FROM [INFORMATION_SCHEMA].[COLUMNS]
        WHERE [TABLE_SCHEMA] = @TBSCHEMA AND [TABLE_NAME] = @TBNAME AND ISNUMERIC([COLUMN_NAME]) = 1
        FOR XML PATH('')), 1, 11, '')
    EXEC(@QUERY)
END


----------------------------------------
CREATE OR ALTER PROCEDURE [GRADIENT].[dot]
    @LTBNAME VARCHAR(MAX),
    @RTBNAME VARCHAR(MAX),
    @RESNAME VARCHAR(MAX) = 'DOTRESULT',
    @TRANSPOSE TINYINT = 0x00
AS
BEGIN
    -- init transpose flags
    DECLARE @TRANSPOSE_LEFT  INT = 0x01
    DECLARE @TRANSPOSE_RIGHT INT = 0x02
    -- flat left matrix
    DROP TABLE IF EXISTS #LFLAT
    CREATE TABLE #LFLAT ([idx] BIGINT, [col] BIGINT, [value] DECIMAL(19,6))
    INSERT INTO #LFLAT EXEC [GRADIENT].[flat] 'GRADIENT', @LTBNAME
    -- flat right matrix
    DROP TABLE IF EXISTS #RFLAT
    CREATE TABLE #RFLAT ([idx] BIGINT, [col] BIGINT, [value] DECIMAL(19,6))
    INSERT INTO #RFLAT EXEC [GRADIENT].[flat] 'GRADIENT', @RTBNAME
    -- check matrix dimensions
    IF (SELECT COUNT(DISTINCT IIF(@TRANSPOSE & @TRANSPOSE_LEFT > 0, [LF].[idx], [LF].[col])) FROM #LFLAT [LF])
            != (SELECT COUNT(DISTINCT IIF(@TRANSPOSE & @TRANSPOSE_RIGHT > 0, [RF].[col], [RF].[idx])) FROM #RFLAT [RF])
        RAISERROR('Matrix dimensions mismatch', 16, 10)
    -- multiple
    DROP TABLE IF EXISTS #TEMP
    CREATE TABLE #TEMP ([idx] BIGINT, [col] BIGINT, [value] DECIMAL(19,6))
    INSERT INTO #TEMP
    SELECT
        [ca].[idx],
        [ca].[col],
        SUM([LF].[value] * [RF].[value])
    FROM #LFLAT [LF]
    JOIN #RFLAT [RF] ON
        IIF(@TRANSPOSE & @TRANSPOSE_LEFT > 0, [LF].[idx], [LF].[col]) = IIF(@TRANSPOSE & @TRANSPOSE_RIGHT > 0, [RF].[col], [RF].[idx])
    CROSS APPLY ( SELECT
        IIF(@TRANSPOSE & @TRANSPOSE_LEFT > 0,  [LF].[col], [LF].[idx]) [idx],
        IIF(@TRANSPOSE & @TRANSPOSE_RIGHT > 0, [RF].[idx], [RF].[col]) [col]
    ) [ca]
    GROUP BY [ca].[idx], [ca].[col]
    -- build result table
    DECLARE @QUERY VARCHAR(MAX)
    SET @QUERY = 'DROP TABLE IF EXISTS [GRADIENT].' + QUOTENAME(@RESNAME) +
        ' CREATE TABLE [GRADIENT].' + QUOTENAME(@RESNAME) + ' ([idx] BIGINT' + (SELECT DISTINCT ', ' + QUOTENAME([col]) + ' DECIMAL(19,6)' FROM #TEMP FOR XML PATH('')) + ')'
    EXEC(@QUERY)
    -- unflat result    
    DECLARE @PVLIST VARCHAR(MAX) = STUFF((SELECT DISTINCT ', ' + QUOTENAME([col]) FROM #TEMP FOR XML PATH('')), 1, 2, '')
    SET @QUERY = (SELECT 'INSERT INTO [GRADIENT].' + QUOTENAME(@RESNAME) + ' SELECT * FROM (SELECT * FROM #TEMP) [t] PIVOT (SUM([value]) FOR [col] IN (' + @PVLIST + ')) [pv]')
    EXEC(@QUERY)
END

    
----------------------------------------
-- TODO
-- stochastic gradient
-- batch normalization
-- regularization (L1, L2)
-- error calculation

CREATE OR ALTER PROCEDURE [GRADIENT].[descent]
    @LEARNING_RATE DECIMAL(19,6) = 0.01,
    @ITERATIONS INT = 250
AS
BEGIN
    -- assert parameters
    IF @LEARNING_RATE <= 0 RAISERROR('Learning rate must be >= 0', 16, 1)
    IF @ITERATIONS <= 0 RAISERROR('Number of iterations must be >= 0', 16, 1)
    -- initialization
    EXEC [GRADIENT].[init]
    
    -- descent
    DECLARE @ITER INT = 0
    WHILE @ITER < @ITERATIONS
    BEGIN
        SET @ITER = @ITER + 1
        -- calc predicts
        EXEC [GRADIENT].[dot] 'Xb', 'W', 'Yb'
        -- calc delta
        DECLARE @FMAP VARCHAR(MAX) = STUFF((SELECT ', [Yb].' + QUOTENAME([COLUMN_NAME]) + ' = [Yb].' + QUOTENAME([COLUMN_NAME]) + ' - [Y].' + QUOTENAME([COLUMN_NAME])
            FROM [INFORMATION_SCHEMA].[COLUMNS]
            WHERE [TABLE_SCHEMA] = 'GRADIENT' AND [TABLE_NAME] = 'Y' AND ISNUMERIC([COLUMN_NAME]) = 1
            FOR XML PATH('')), 1, 2, '')
        EXEC('UPDATE [GRADIENT].[Yb] SET ' + @FMAP + ' FROM [GRADIENT].[Yb] JOIN [GRADIENT].[Y] ON [Y].[idx] = [Yb].[idx]')
        -- calculate gradient and update weights
        EXEC [GRADIENT].[dot] 'Xb', 'Yb', 'dQ', 1
        SET @FMAP = STUFF((SELECT ', [W].' + QUOTENAME([COLUMN_NAME]) + ' = [W].' + QUOTENAME([COLUMN_NAME]) + ' - ' + CAST(@LEARNING_RATE AS VARCHAR(MAX)) + ' / ' + (SELECT CAST(COUNT(*) AS VARCHAR(MAX)) FROM [GRADIENT].[Y]) + ' * [dQ].' + QUOTENAME([COLUMN_NAME])
            FROM [INFORMATION_SCHEMA].[COLUMNS]
            WHERE [TABLE_SCHEMA] = 'GRADIENT' AND [TABLE_NAME] = 'dQ' AND ISNUMERIC([COLUMN_NAME]) = 1
            FOR XML PATH('')), 1, 2, '')
        EXEC('UPDATE [GRADIENT].[W] SET ' + @FMAP + ' FROM [GRADIENT].[W] JOIN [GRADIENT].[dQ] ON [dQ].[idx] = [W].[idx]')
    END
END
