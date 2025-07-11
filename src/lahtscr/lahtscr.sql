CREATE OR REPLACE PROCEDURE lahtscr (
    IN tsname VARCHAR(20)
)
BEGIN
    DECLARE stmt               VARCHAR(1000);
    DECLARE ts_count           INT DEFAULT 0;
    DECLARE sg_count           INT DEFAULT 0;
    DECLARE sgname             VARCHAR(20);
    DECLARE dir                VARCHAR(50);
    DECLARE tablespace_limit   INT CONSTANT 3;
    DECLARE SQLCODE            INT DEFAULT 0;

--    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
--        SET status = 'FAIL';

    -- 1. Get number of existing storage groups named sg%
    SELECT COUNT(*) INTO sg_count
    FROM SYSCAT.STOGROUPS
    WHERE SGNAME LIKE 'SG%';

    -- If no storage groups yet, set sg_count = 1 (for sg1)
    IF sg_count = 0 THEN
        SET sg_count = 1;
        SET sgname = 'SG1';
        SET dir = '/ars/data/db1/sg1';

        SET stmt = 'CREATE STOGROUP ' || sgname || ' ON ''' || dir || ''' set as default';
        EXECUTE IMMEDIATE stmt;

--        SET stmt = 'ALTER DATABASE CONFIGURE USING DFT_STORAGE_GROUP ' || sgname;
--        EXECUTE IMMEDIATE stmt;
    ELSE
        -- 2. Check how many tablespaces are using sgN

        select count(*) into ts_count 
        from SYSCAT.TABLESPACES 
        where sgname in 
            (select sgname 
             from syscat.stogroups 
             where defaultsg='Y');

        -- 3. If the count is >= 32000, create sgN+1
        IF ts_count >= tablespace_limit THEN
            SET sg_count = sg_count + 1;
            SET sgname = 'SG' || sg_count;
            SET dir = '/ars/data/db1/sg' || sg_count;

            -- Create new storage group
            SET stmt = 'CREATE STOGROUP ' || sgname || ' ON ''' || dir || ''' set as default';
            EXECUTE IMMEDIATE stmt;

            -- Set as default
--            SET stmt = 'ALTER DATABASE CONFIGURE USING DFT_STORAGE_GROUP ' || sgname;
--            EXECUTE IMMEDIATE stmt;
        END IF;
    END IF;

    -- 4. Create the tablespace in the selected storage group
    SET stmt = 'CREATE TABLESPACE ' || tsname;
	EXECUTE IMMEDIATE stmt;
--    SET status = 'SUCCESS';
END;
@