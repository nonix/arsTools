
CONNECT TO ARCHIVE;

------------------------------------------------
-- DDL Statements for Table "ODADM   "."SCEXPRULES"
------------------------------------------------
 

CREATE TABLE "ODADM   "."SCEXPRULES"  (
		  "SEARCHFOL" VARCHAR(60) NOT NULL , 
		  "SEARCHFLD" VARCHAR(60) NOT NULL WITH DEFAULT '' , 
		  "TYPE" SMALLINT NOT NULL WITH DEFAULT 1 , 
		  "RULEFLD" VARCHAR(60) NOT NULL WITH DEFAULT '' , 
		  "RULEVAL" VARCHAR(255) NOT NULL WITH DEFAULT '' , 
		  "ANNOTATION" VARCHAR(1024) )   
		 IN "ODADM_SL9"  
		 ORGANIZE BY ROW; 

-- DDL Statements for Indexes on Table "ODADM   "."SCEXPRULES"

SET SYSIBM.NLS_STRING_UNITS = 'SYSTEM';

CREATE INDEX "ODADM   "."SCEXPRULES_IX1" ON "ODADM   "."SCEXPRULES" 
		("SEARCHFLD" ASC,
		 "RULEFLD" ASC,
		 "SEARCHFOL" ASC)
		
		COMPRESS NO 
		INCLUDE NULL KEYS ALLOW REVERSE SCANS;

COMMIT WORK;

CONNECT RESET;

TERMINATE;

