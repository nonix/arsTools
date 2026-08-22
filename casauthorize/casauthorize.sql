connect to ODLZACH1;
	CREATE or replace FUNCTION casauthorize (
		userid   CHAR(9),
		bcnr     CHAR(4),
		kontonr  CHAR(8)
	)
	RETURNS SMALLINT
	SPECIFIC casauthorize
	EXTERNAL NAME '/ars/odadm/sqllib/function/libcasauthorize.so!casauthorize'
	LANGUAGE C
	PARAMETER STYLE SQL
	DETERMINISTIC
	NO SQL
	NO EXTERNAL ACTION
	FENCED
	ALLOW PARALLEL
	NO SCRATCHPAD
	FINAL CALL
	NULL CALL;
terminate;
