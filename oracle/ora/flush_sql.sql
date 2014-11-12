/*[[flush a sql from out of shared pool, you can also rebuild index to archive this purpose. Usage: flush_sql <sql_id> 
--[[@version: 10.2.0.4={} ]]--
]]*/
DECLARE
    NAME    VARCHAR2(50);
    version VARCHAR2(3);
BEGIN
    SELECT regexp_replace(version, '\..*') INTO version FROM v$instance;

    SELECT MAX(address || ',' || hash_value) INTO NAME FROM v$sqlarea WHERE sql_id = :V1;

    IF NAME IS NOT NULL THEN
        IF version + 0 = 10 THEN
            EXECUTE IMMEDIATE q'[alter session set events '5614566 trace name context forever']'; -- bug fix for 10.2.0.4 backport
        END IF;
        sys.dbms_shared_pool.purge(NAME, 'C', 1);
        IF version + 0 = 10 THEN
            EXECUTE IMMEDIATE q'[alter session set events '5614566 trace name context off']';
        END IF;
    END IF;
END;
/