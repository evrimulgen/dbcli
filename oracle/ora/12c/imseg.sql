/*[[Show inmemory info of a specific table. Usage: @@NAME [owner.]<table_name>[.partition_name] [column_name|*] [-d] [-f"filter"]
   -d: details into instance level
   
   Some parameters to control the in-memory behaviors:
   * inmemory_size
   * inmemory_query
   * inmemory_force
   * IMSS: _inmemory_dynamic_scans(AUTO/DISABLE/FORCE)
   * IMA: _always_vector_transformation(default false)
   * IMA: _key_vector_predicate_enabled
   * IMA: _optimizer_vector_transformation
   * IME: inmemory_expressions_usage
   * IME: inmemory_virtual_columns
   * POP: inmemory_trickle_repopulate_servers_percent
   * POP: inmemory_max_populate_servers
   * GD : _globaldict_enable(0:disable,1: JoinGroups Only, 2:ALL)
   * NUMBER for QUERY LOW: inmemory_optimized_arithmetic
   * PushDownAgg: _kdz_pcode_flags
          0x001 : No PCODE
          0x002 : No range pred eval
          0x004 : No reorder preds
          0x008 : No selective eval
          0x010 : No LIKE push-down
          0x020 : No agg/gby push-down
          0x040 : No constant fold opt
          0x080 : No popcnt use for eval
          0x100 : No complex eva push-down
          0x200 : No proj rowset push-down
          0x400 : No IME pcode support
          0x800 : Dict engine for proj
         0x1000 : Atomized proj exprs
         0x2000 : No lob pred push-down
         0x4000 : Don't save in cursor
         0x8000 : Enable pcode compilation for HCC / CC1 tables.
        0x10000 : No selective dict eval
        0x20000 : No deferred constants 
   IME Operations:
       EXEC DBMS_INMEMORY_ADMIN.IME_OPEN_CAPTURE_WINDOW;
       EXEC DBMS_INMEMORY_ADMIN.IME_CLOSE_CAPTURE_WINDOW;
       EXEC DBMS_INMEMORY_ADMIN.IME_POPULATE_EXPRESSIONS;
       EXEC DBMS_INMEMORY_ADMIN.IME_CAPTURE_EXPRESSIONS('WINDOW/CUMULATIVE/CURRENT');
       EXEC DBMS_INMEMORY_ADMIN.IME_OPEN_CAPTURE_WINDOW;
   
   --[[
       @check_access_obj: cdb_objects={cdb_} dba_objects={dba_} default={all_}
       @check_access_exp: DBA_IM_EXPRESSIONS={DBA_IM_EXPRESSIONS} default={USER_IM_EXPRESSIONS}
       @check_access_jp:  CDB_JOINGROUPS={CDB_JOINGROUPS} DBA_JOINGROUPS={DBA_JOINGROUPS} default={USER_JOINGROUPS}
       @ver: 18={,SUM(NUMDELTA) DELTA} 12.1={}
       &inst1 : default={listagg(inst_id,',') within group(order by inst_id)} d={inst_id}
       &inst2 : default={} d={,inst_id}
       &imcu  : default={} d={MAX(IMCU_ADDR) IMCU_ADDR,}
       &filter: default={1=1} f={}
   --]]
]]*/
ORA _find_object "&V1"

SET FEED OFF verify off
col allocate,cu_used,col_used format kmg
col data_rows,blocks,invalid,scans,distcnt,EVALUATION_COUNT format %,.0f

var cols1  VARCHAR
var cols2  VARCHAR
var typs   VARCHAR
var target VARCHAR
var mins   VARCHAR
var cnv    VARCHAR
DECLARE
    cols VARCHAR2(32767) := 'DECODE(col#';
    cnv  VARCHAR2(32767) := 'DECODE(col#';
    typs VARCHAR2(32767) := 'DECODE(col#';
    mins VARCHAR2(32767) := '';
    cnt  PLS_INTEGER     := 0;
BEGIN
    IF :OBJECT_TYPE not like 'TABLE%' THEN
        raise_application_error(-20001,'Invalid object type:'||:OBJECT_TYPE);
    END IF;
    FOR R IN (SELECT COLUMN_NAME n, INTERNAL_COLUMN_ID CID,data_type
              FROM   &check_access_obj.tab_cols a
              WHERE  owner = :object_owner
              AND    table_name = :object_name
              AND    column_name in(select distinct column_name from gv$im_column_level b where a.owner=b.owner and a.table_name=b.table_name and INMEMORY_COMPRESSION!='NO INMEMORY')
              AND    HIDDEN_COLUMN = 'NO'
              ORDER  BY 2) LOOP
        cols := cols || ',' || r.cid || ',"' || r.n || '"';
        typs := typs || ',' || r.cid || ',''' || r.data_type || '''';
        cnv  := cnv || ',' || r.cid || ',min'|| r.cid;
        mins := mins || ',''''||' || 'min("' || r.n || '") min'||r.cid || ',' || '''''||max("' || r.n || '") max'||r.cid || ',' || 'count(distinct "' || r.n || '") dist'||r.cid;
        cnt  := cnt + 1;
    END LOOP;
    
    IF cnt = 0 THEN
        raise_application_error(-20001,'The table has not been populated, or is not an in-memory table!');
    END IF;
    cnv    := cnv||') act_min';
    :cnv   := replace(cnv,'min','dist')||','||cnv||','||replace(cnv,'min','max');
    cols   := cols || ',-1,null)';
    :cols1 := cols;
    :cols2 := replace(cols,'"','''');
    :mins  := trim(',' from mins);
    :typs  := typs||')';
    :target:= :object_owner||'.'||:object_name||nullif(' PARTITION('||:object_subname||')',' PARTITION()');
END;
/

var c1 refcursor "IMCU & IMSMU Summary";
var c2 refcursor "IM Expressions";
var c3 refcursor "IM Join Groups";
var c4 refcursor "IM Expression Stats"
DECLARE
    c2    SYS_REFCURSOR;
    c3    SYS_REFCURSOR;
    c4    SYS_REFCURSOR;
    cname VARCHAR2(128) := UPPER(:V2);
    own   VARCHAR2(128) := :object_owner;
    oname VARCHAR2(128) := :object_name;
    sub   VARCHAR2(128) := :object_subname; 
    dtype VARCHAR2(300);
    oid   INT := :object_id;
    did   INT := :object_data_id;
    cid   INT;
BEGIN
    $IF dbms_db_version.version>12 OR dbms_db_version.release>1 $THEN
    OPEN c2 FOR
        SELECT *
        FROM   &check_access_exp
        WHERE  object_number = oid
        AND    UPPER(column_name) = NVL(nullif(cname,'*'), UPPER(column_name));
    OPEN c3 FOR
        WITH gp AS
         (SELECT *
          FROM   &check_access_jp
          WHERE  table_owner = own
          AND    table_name = oname
          AND    UPPER(column_name) = NVL(nullif(cname,'*'), UPPER(column_name)))
        SELECT * FROM &check_access_jp WHERE GD_ADDRESS IN (SELECT GD_ADDRESS FROM gp) ORDER BY GD_ADDRESS, flags;
    OPEN c4 FOR 
        SELECT * FROM &check_access_obj.EXPRESSION_STATISTICS
        WHERE  owner = own
        AND    table_name = oname
        AND   (nullif(cname,'*') IS NULL OR upper(EXPRESSION_TEXT) LIKE '%"'||cname||'"%');
    $END
    
    :c2 := c2;
    :c3 := c3;
    :c4 := c4;

    IF cname IS NULL THEN
        OPEN :c1 FOR
            WITH objs AS
             (SELECT object_id objn, data_object_id objd, owner, object_name table_name, subobject_name part
              FROM   &check_access_obj.objects a
              WHERE  object_name = oname
              AND    owner = own
              AND    (sub IS NULL OR subobject_name = sub)),
            im AS
             (SELECT *
              FROM   gv$(CURSOR (
                          SELECT /*+ordered use_hash(h0 m h1)*/
                                 USERENV('instance') inst_id,
                                 h0.IMCU_ADDR,
                                 h0.HEAD_PIECE_ADDRESS,
                                 h0.NUM_COLS,
                                 h0.ALLOCATED_LEN,
                                 h0.used_len,
                                 h1.*,
                                 /*--BAD performance
                                 (SELECT COUNT(1) FROM v$imeu_header h2 
                                  WHERE  h2.objd=h0.objd
                                  AND    h2.IS_HEAD_PIECE>0
                                  AND    h2.IMEU_ADDR=h0.IMCU_ADDR) IMEUs,*/
                                 dbms_utility.data_block_address_file(sdba) file#,
                                 dbms_utility.data_block_address_block(sdba) block#,
                                 dbms_rowid.rowid_create(1,h0.objd,
                                                         dbms_utility.data_block_address_file(sdba),
                                                         dbms_utility.data_block_address_block(sdba),
                                                         1) start_rowid,
                                 dbms_rowid.rowid_create(1,h0.objd,
                                                         dbms_utility.data_block_address_file(edba),
                                                         dbms_utility.data_block_address_block(edba+1),
                                                         1) end_rowid                        
                          FROM   (SELECT h.*, to_number(IMCU_ADDR, lpad('X', 16, 'X')) addr
                                  FROM   V$IM_HEADER h
                                  WHERE  (table_objn = OID OR objd = did)
                                  AND    IS_HEAD_PIECE > 0) h0,
                                 LATERAL (SELECT DATAOBJ, 
                                                 MIN(start_dba) sdba,
                                                 MAX(end_dba) edba
                                          FROM   v$im_tbs_ext_map m
                                          WHERE  h0.addr = m.IMCU_ADDR
                                          AND    h0.objd = m.dataobj
                                          GROUP  BY DATAOBJ,IMCU_ADDR) m,
                                 LATERAL (SELECT DISTINCT *
                                          FROM   V$IM_SMU_HEAD h1
                                          WHERE  m.dataobj = h1.objd
                                          AND    m.sdba = h1.startdba) h1)))
            SELECT &inst1 inst,
                   o.objd dataobj,
                   part,
                   '|' "|",
                   MAX(IMCU_ADDR) IMCU_ADDR,
                   MAX(NUM_COLS) cols,
                   AVG(ALLOCATED_LEN) allocate,
                   AVG(USED_LEN) cu_used,
                   startdba,
                   --MAX(file#) file#,
                   --MAX(block#) block#,
                   MIN(START_ROWID) START_ROWID,
                   MAX(END_ROWID) END_ROWID,
                   AVG(EXTENT_CNT) EXTENTs,
                   AVG(BLOCK_CNT) blocks,
                   AVG(INVALID_BLOCKS) INVALID,
                   '|' "|",
                   AVG(TOTAL_ROWS) DATA_ROWS,
                   AVG(INVALID_ROWS) INVALID,
                   '|' "|",
                   AVG(SCANCNT) SCANS,
                   AVG(INVALID) INVALID,
                   AVG(REPOPSUB) REPOPSUB,
                   AVG(CHUNKS) CHUNKS,
                   AVG(FINAL) FINAL,
                   AVG(CLONECNT) CLONES &ver
            FROM   objs o, im
            WHERE  o.objd = im.objd
            AND    inst_id=nvl(:instance,inst_id)
            AND    (&filter)
            GROUP  BY o.objd, owner, table_name, startdba, part &inst2
            ORDER  BY o.objd, startdba &inst2;
    ELSIF cname='*' THEN
        OPEN :c1 FOR q'{
            WITH objs AS
             (SELECT object_id objn, data_object_id objd, owner, object_name table_name, subobject_name part
              FROM   &check_access_obj.objects a
              WHERE  object_name = :oname
              AND    owner = :own
              AND    (:sub IS NULL OR subobject_name = :sub)),
            ima AS
             (SELECT /*+materialize*/ *
              FROM   gv$(CURSOR
                         (SELECT /*+ordered use_hash(h0 cu m h1)*/
                           USERENV('instance') inst_id,
                           h0.IMCU_ADDR,
                           h0.HEAD_PIECE_ADDRESS,
                           h0.NUM_COLS,
                           h0.ALLOCATED_LEN,
                           h0.used_len,
                           h1.*,
                           col#,
                           dbms_utility.data_block_address_file(sdba) file#,
                           dbms_utility.data_block_address_block(sdba) block#,
                           dbms_rowid.rowid_create(1,h0.objd,
                                                   dbms_utility.data_block_address_file(sdba),
                                                   dbms_utility.data_block_address_block(sdba),
                                                   1) start_rowid,
                           dbms_rowid.rowid_create(1,h0.objd,
                                                   dbms_utility.data_block_address_file(edba),
                                                   dbms_utility.data_block_address_block(edba + 1),
                                                   1) end_rowid,
                           cu.DICTIONARY_ENTRIES DISTINCTS,
                           cu.SEGMENT_DICTIONARY_ADDRESS,
                           cu.LENGTH CLENGTH,
                           DECODE(&typs,
                                'NUMBER',to_char(utl_raw.cast_to_number(MINIMUM_VALUE)),
                                'FLOAT',to_char(utl_raw.cast_to_number(MINIMUM_VALUE)),
                                'VARCHAR2',to_char(utl_raw.cast_to_varchar2(MINIMUM_VALUE)),
                                'NVARCHAR2',to_char(utl_raw.cast_to_nvarchar2(MINIMUM_VALUE)),
                                'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(MINIMUM_VALUE)),
                                'BINARY_FLOAT',to_char(utl_raw.cast_to_binary_float(MINIMUM_VALUE)),
                                'TIMESTAMP',
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 1, 2), 'XX') - 100, 2, 0) ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 3, 2), 'XX') - 100, 2, 0) || '-' ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 5, 2), 'XX'), 2, 0) || '-' ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 7, 2), 'XX'), 2, 0) || ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 9, 2), 'XX') - 1, 2, 0) || ':' ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 11, 2), 'XX') - 1, 2, 0) || ':' ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 13, 2), 'XX') - 1, 2, 0) || '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 15, 8), 'XXXXXXXX'), 1, 6), '0'),
                                'TIMESTAMP WITH TIME ZONE',
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 1, 2), 'XX') - 100, 2, 0) ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 3, 2), 'XX') - 100, 2, 0) || '-' ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 5, 2), 'XX'), 2, 0) || '-' ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 7, 2), 'XX'), 2, 0) || ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 9, 2), 'XX') - 1, 2, 0) || ':' ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 11, 2), 'XX') - 1, 2, 0) || ':' ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 13, 2), 'XX') - 1, 2, 0) || '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 15, 8), 'XXXXXXXX'), 1, 6), '0') || ' ' ||
                                    nvl(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 23, 2), 'XX') - 20, 0) || ':' ||
                                    nvl(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 25, 2), 'XX') - 60, 0),
                                'DATE',
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 1, 2), 'XX') - 100, 2, 0) ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 3, 2), 'XX') - 100, 2, 0) || '-' ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 5, 2), 'XX'), 2, 0) || '-' ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 7, 2), 'XX'), 2, 0) || ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 9, 2), 'XX') - 1, 2, 0) || ':' ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 11, 2), 'XX') - 1, 2, 0) || ':' ||
                                    lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 13, 2), 'XX') - 1, 2, 0),
                                    '' || MINIMUM_VALUE) min_v,
                           DECODE(&typs,
                                'NUMBER',to_char(utl_raw.cast_to_number(MAXIMUM_VALUE)),
                                'FLOAT',to_char(utl_raw.cast_to_number(MAXIMUM_VALUE)),
                                'VARCHAR2',to_char(utl_raw.cast_to_varchar2(MAXIMUM_VALUE)),
                                'NVARCHAR2',to_char(utl_raw.cast_to_nvarchar2(MAXIMUM_VALUE)),
                                'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(MAXIMUM_VALUE)),
                                'BINARY_FLOAT',to_char(utl_raw.cast_to_binary_float(MAXIMUM_VALUE)),
                                'TIMESTAMP',
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 1, 2), 'XX') - 100, 2, 0) ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 3, 2), 'XX') - 100, 2, 0) || '-' ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 5, 2), 'XX'), 2, 0) || '-' ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 7, 2), 'XX'), 2, 0) || ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 9, 2), 'XX') - 1, 2, 0) || ':' ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 11, 2), 'XX') - 1, 2, 0) || ':' ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 13, 2), 'XX') - 1, 2, 0) || '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 15, 8), 'XXXXXXXX'), 1, 6), '0'),
                                'TIMESTAMP WITH TIME ZONE',
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 1, 2), 'XX') - 100, 2, 0) ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 3, 2), 'XX') - 100, 2, 0) || '-' ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 5, 2), 'XX'), 2, 0) || '-' ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 7, 2), 'XX'), 2, 0) || ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 9, 2), 'XX') - 1, 2, 0) || ':' ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 11, 2), 'XX') - 1, 2, 0) || ':' ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 13, 2), 'XX') - 1, 2, 0) || '.' ||
                                    nvl(substr(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 15, 8), 'XXXXXXXX'), 1, 6), '0') || ' ' ||
                                    nvl(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 23, 2), 'XX') - 20, 0) || ':' ||
                                    nvl(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 25, 2), 'XX') - 60, 0),
                                'DATE',
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 1, 2), 'XX') - 100, 2, 0) ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 3, 2), 'XX') - 100, 2, 0) || '-' ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 5, 2), 'XX'), 2, 0) || '-' ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 7, 2), 'XX'), 2, 0) || ' ' ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 9, 2), 'XX') - 1, 2, 0) || ':' ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 11, 2), 'XX') - 1, 2, 0) || ':' ||
                                    lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 13, 2), 'XX') - 1, 2, 0),
                                    '' || MAXIMUM_VALUE) max_v
                          FROM   (SELECT h.*, to_number(IMCU_ADDR, lpad('X', 16, 'X')) addr
                                  FROM   V$IM_HEADER h
                                  WHERE  (table_objn = :OID OR objd = :did)
                                  AND    IS_HEAD_PIECE > 0) h0,
                                 LATERAL (SELECT cu.*,cu.COLUMN_NUMBER col#
                                          FROM   v$im_col_cu cu
                                          WHERE  h0.HEAD_PIECE_ADDRESS = CU.HEAD_PIECE_ADDRESS
                                          AND    h0.OBJD = cu.OBJD) cu,
                                 LATERAL (SELECT DATAOBJ, 
                                                 MIN(start_dba) sdba,
                                                 MAX(end_dba) edba
                                          FROM   v$im_tbs_ext_map m
                                          WHERE  h0.addr = m.IMCU_ADDR
                                          AND    h0.objd = m.dataobj
                                          GROUP  BY DATAOBJ,IMCU_ADDR) m,
                                 LATERAL (SELECT DISTINCT *
                                          FROM   V$IM_SMU_HEAD h1
                                          WHERE  m.dataobj = h1.objd
                                          AND    m.sdba = h1.startdba) h1))),
            dict AS
             (SELECT a.*,
                     (SELECT COUNT(1) - 1
                      FROM   ima b
                      WHERE  a.inst_id = b.inst_id
                      AND    a.col#=b.col#
                      AND    (&typs IN ('NUMBER', 'FLOAT', 'BINARY_DOUBLE', 'BINARY_FLOAT', 'BINARY_INTEGER') AND
                            (b.min_v + 0 BETWEEN a.min_v + 0 AND a.max_v + 0 OR b.max_v + 0 BETWEEN a.min_v + 0 AND a.max_v + 0) OR
                            &typs NOT IN ('NUMBER', 'FLOAT', 'BINARY_DOUBLE', 'BINARY_FLOAT', 'BINARY_INTEGER') AND
                            (b.min_v BETWEEN a.min_v AND a.max_v OR b.max_v BETWEEN a.min_v AND a.max_v))) Overlaps
              FROM   ima a
              WHERE  inst_id = nvl(:inst, inst_id))
            SELECT distinct 
                   IMCU_ADDR,startdba,
                   start_rowid,
                   end_rowid,
                   TOTAL_ROWS,
                   col#,
                   &cols2 COLUMN_NAME,
                   distincts distincts,
                   '*' "*",
                   Overlaps,
                   substr(min_v,1,32) min_v,
                   substr(max_v,1,32) max_v
            FROM   dict
            ORDER  BY 1,2,col#}' using oname,own,sub,sub,oid,did,:instance;         
    ELSE
        SELECT max(INTERNAL_COLUMN_ID), max(DATA_TYPE)
        INTO   cid, dtype
        FROM   &check_access_obj.tab_cols
        WHERE  owner = own
        AND    table_name = oname
        AND    upper(column_name) = cname;
        
        IF cid IS NULL THEN
            raise_application_error(-20001,'No such column: '||:V2);
        END IF;
    
        OPEN :c1 FOR
            WITH objs AS
             (SELECT object_id objn, data_object_id objd, owner, object_name table_name, subobject_name part
              FROM   &check_access_obj.objects a
              WHERE  object_name = oname
              AND    owner = own
              AND    (sub IS NULL OR subobject_name = sub)),
            ima AS
             (SELECT /*+materialize*/ * 
              FROM   gv$(CURSOR (
                          SELECT /*+ordered use_hash(h0 cu m h1)*/
                                 USERENV('instance') inst_id,
                                 h0.IMCU_ADDR,
                                 h0.HEAD_PIECE_ADDRESS,
                                 h0.NUM_COLS,
                                 h0.ALLOCATED_LEN,
                                 h0.used_len,
                                 h1.*,
                                 /*--BAD performance
                                  (SELECT listagg(SQL_EXPRESSION,chr(10)) within group(order by SQL_EXPRESSION)
                                  FROM   v$imeu_header h2, v$im_imecol_cu eu
                                  WHERE  h2.objd=h0.objd
                                  AND    h2.IS_HEAD_PIECE>0
                                  AND    h2.IMEU_ADDR=h0.IMCU_ADDR
                                  AND    h2.HEAD_PIECE_ADDRESS=eu.IMEU_HEAD_PIECE_ADDR
                                  AND    eu.objd=h0.objd
                                  AND    INTERNAL_COLUMN_NUMBER=cid) EXPR,*/
                                 dbms_utility.data_block_address_file(sdba) file#,
                                 dbms_utility.data_block_address_block(sdba) block#,
                                 dbms_rowid.rowid_create(1,h0.objd,
                                                         dbms_utility.data_block_address_file(sdba),
                                                         dbms_utility.data_block_address_block(sdba),
                                                         1) start_rowid,
                                 dbms_rowid.rowid_create(1,h0.objd,
                                                         dbms_utility.data_block_address_file(edba),
                                                         dbms_utility.data_block_address_block(edba+1),
                                                         1) end_rowid,
                                 cu.DICTIONARY_ENTRIES,
                                 cu.MIN_V,
                                 cu.MAX_V,
                                 cu.SEGMENT_DICTIONARY_ADDRESS,
                                 cu.LENGTH CLENGTH
                          FROM   (SELECT h.*, to_number(IMCU_ADDR, lpad('X', 16, 'X')) addr
                                  FROM   V$IM_HEADER h
                                  WHERE  (table_objn = OID OR objd = did)
                                  AND    IS_HEAD_PIECE > 0) h0,
                                 LATERAL (SELECT cu.*,
                                         decode(dtype
                                              ,'NUMBER'       ,to_char(utl_raw.cast_to_number(MINIMUM_VALUE))
                                              ,'FLOAT'        ,to_char(utl_raw.cast_to_number(MINIMUM_VALUE))
                                              ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(MINIMUM_VALUE))
                                              ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(MINIMUM_VALUE))
                                              ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(MINIMUM_VALUE))
                                              ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(MINIMUM_VALUE))
                                              ,'TIMESTAMP'    , lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 1, 2), 'XX')-100,2,0)||
                                                                lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                                                lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 5, 2), 'XX') ,2,0)|| '-' ||
                                                                lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 7, 2), 'XX') ,2,0)|| ' ' ||
                                                                lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                                                lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                                                lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 13, 2), 'XX')-1,2,0)|| '.' ||
                                                                nvl(substr(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 15, 8), 'XXXXXXXX'),1,6),'0')
                                              ,'TIMESTAMP WITH TIME ZONE',
                                                                lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 1, 2), 'XX')-100,2,0)||
                                                                lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                                                lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 5, 2), 'XX'),2,0)|| '-' ||
                                                                lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 7, 2), 'XX'),2,0)|| ' ' ||
                                                                lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                                                lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                                                lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 13, 2), 'XX')-1,2,0)|| '.' ||
                                                                nvl(substr(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 15, 8), 'XXXXXXXX'),1,6),'0')||' '||
                                                                nvl(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 23,2),'XX')-20,0)||':'||
                                                                nvl(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 25, 2), 'XX')-60,0)
                                              ,'DATE',lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 1, 2), 'XX')-100,2,0)||
                                                      lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                                      lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 5, 2), 'XX') ,2,0)|| '-' ||
                                                      lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 7, 2), 'XX') ,2,0)|| ' ' ||
                                                      lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                                      lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                                      lpad(TO_NUMBER(SUBSTR(MINIMUM_VALUE, 13, 2), 'XX')-1,2,0)
                                              ,  ''||MINIMUM_VALUE) min_v,
                                            decode(dtype
                                              ,'NUMBER'       ,to_char(utl_raw.cast_to_number(MAXIMUM_VALUE))
                                              ,'FLOAT'        ,to_char(utl_raw.cast_to_number(MAXIMUM_VALUE))
                                              ,'VARCHAR2'     ,to_char(utl_raw.cast_to_varchar2(MAXIMUM_VALUE))
                                              ,'NVARCHAR2'    ,to_char(utl_raw.cast_to_nvarchar2(MAXIMUM_VALUE))
                                              ,'BINARY_DOUBLE',to_char(utl_raw.cast_to_binary_double(MAXIMUM_VALUE))
                                              ,'BINARY_FLOAT' ,to_char(utl_raw.cast_to_binary_float(MAXIMUM_VALUE))
                                              ,'TIMESTAMP'    , lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 1, 2), 'XX')-100,2,0)||
                                                                lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                                                lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 5, 2), 'XX') ,2,0)|| '-' ||
                                                                lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 7, 2), 'XX') ,2,0)|| ' ' ||
                                                                lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                                                lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                                                lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 13, 2), 'XX')-1,2,0)|| '.' ||
                                                                nvl(substr(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 15, 8), 'XXXXXXXX'),1,6),'0')
                                              ,'TIMESTAMP WITH TIME ZONE',
                                                                lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 1, 2), 'XX')-100,2,0)||
                                                                lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                                                lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 5, 2), 'XX'),2,0)|| '-' ||
                                                                lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 7, 2), 'XX'),2,0)|| ' ' ||
                                                                lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                                                lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                                                lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 13, 2), 'XX')-1,2,0)|| '.' ||
                                                                nvl(substr(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 15, 8), 'XXXXXXXX'),1,6),'0')||' '||
                                                                nvl(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 23,2),'XX')-20,0)||':'||
                                                                nvl(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 25, 2), 'XX')-60,0)
                                              ,'DATE',lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 1, 2), 'XX')-100,2,0)||
                                                      lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 3, 2), 'XX')-100,2,0)|| '-' ||
                                                      lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 5, 2), 'XX') ,2,0)|| '-' ||
                                                      lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 7, 2), 'XX') ,2,0)|| ' ' ||
                                                      lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 9, 2), 'XX')-1,2,0)|| ':' ||
                                                      lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 11, 2), 'XX')-1,2,0)|| ':' ||
                                                      lpad(TO_NUMBER(SUBSTR(MAXIMUM_VALUE, 13, 2), 'XX')-1,2,0)
                                              ,  ''||MAXIMUM_VALUE) max_v
                                          FROM   v$im_col_cu cu
                                          WHERE  h0.HEAD_PIECE_ADDRESS = CU.HEAD_PIECE_ADDRESS
                                          AND    h0.OBJD = cu.OBJD
                                          AND    cu.COLUMN_NUMBER = cid) cu,
                                 LATERAL (SELECT DATAOBJ, 
                                                 MIN(start_dba) sdba,
                                                 MAX(end_dba) edba
                                          FROM   v$im_tbs_ext_map m
                                          WHERE  h0.addr = m.IMCU_ADDR
                                          AND    h0.objd = m.dataobj
                                          GROUP  BY DATAOBJ,IMCU_ADDR) m,
                                 LATERAL (SELECT DISTINCT *
                                          FROM   V$IM_SMU_HEAD h1
                                          WHERE  m.dataobj = h1.objd
                                          AND    m.sdba = h1.startdba) h1))),
            im AS(
               SELECT a.*,
                  (SELECT count(1)-1 
                   FROM  ima b 
                   WHERE a.inst_id=b.inst_id
                   AND  (
                      dtype in('NUMBER','FLOAT','BINARY_DOUBLE','BINARY_FLOAT','BINARY_INTEGER')
                          AND (b.min_v+0 between a.min_v+0 and a.max_v+0 or 
                               b.max_v+0 between a.min_v+0 and a.max_v+0)
                      OR 
                      dtype not in('NUMBER','FLOAT','BINARY_DOUBLE','BINARY_FLOAT','BINARY_INTEGER')
                          AND (b.min_v between a.min_v and a.max_v or 
                               b.max_v between a.min_v and a.max_v)
                   )) Overlaps
               FROM ima a
               WHERE inst_id=nvl(:instance,inst_id))
            SELECT &inst1 inst,
                   o.objd dataobj,
                   part,
                   '|' "|",
                   &IMCU
                   AVG(ALLOCATED_LEN) allocate,
                   AVG(USED_LEN) cu_used,
                   AVG(CLENGTH) col_used,
                   startdba,
                   min(start_rowid) start_rowid,
                   max(end_rowid) end_rowid,
                   AVG(BLOCK_CNT) blocks,
                   AVG(INVALID_BLOCKS) INVALID,
                   '|' "|",
                   AVG(TOTAL_ROWS) DATA_ROWS,
                   AVG(DICTIONARY_ENTRIES) distcnt,
                   AVG(INVALID_ROWS) INVALID,
                   '|' "|",
                   decode(MAX('' || SEGMENT_DICTIONARY_ADDRESS), '00', 'GD', 'GD+JG') dict,
                   MIN(MIN_V) MIN_V,
                   MAX(MAX_V) MAX_V,
                   max(Overlaps) Overlaps
            FROM   objs o, im a
            WHERE  o.objd = a.objd
            AND    (&filter)
            GROUP  BY o.objd, owner, table_name, startdba, part &inst2
            ORDER  BY o.objd, startdba &inst2;
    END IF;
END;
/

set rownum on printsize 5000
print c1
set rownum off
print c2
print c3
print c4