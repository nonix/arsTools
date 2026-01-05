connect to odlzach1;
CREATE OR REPLACE FUNCTION str2arsdate
(
    IN buf     VARCHAR(80),
    IN defval  INTEGER
)
RETURNS INTEGER
LANGUAGE C
EXTERNAL NAME 'liblah.so!str2arsdate'
PARAMETER STYLE SQL
NO SQL
DETERMINISTIC
FENCED
THREADSAFE
;
select str2arsdate('20260105',10) from sysibm.sysdummy1;
terminate;
