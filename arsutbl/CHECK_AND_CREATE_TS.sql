CREATE OR REPLACE PROCEDURE CHECK_AND_CREATE_TS (IN TS_NAME VARCHAR(128))
LANGUAGE SQL
BEGIN
    DECLARE v_count INT DEFAULT 0;
    DECLARE v_sql   VARCHAR(1000);

    -- Check if the tablespace already exists in the catalog
    SELECT COUNT(*) INTO v_count
    FROM SYSCAT.TABLESPACES
    WHERE TBSPACE = UPPER(TS_NAME);

    IF v_count = 0 THEN
        -- Build CREATE TABLESPACE SQL dynamically
        SET v_sql = 'CREATE TABLESPACE ' || UPPER(TS_NAME) || 
                    ' MANAGED BY AUTOMATIC STORAGE';

        -- Execute the dynamic SQL
        EXECUTE IMMEDIATE v_sql;
    END IF;
END
@

