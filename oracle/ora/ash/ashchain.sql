/*[[
Show ash wait chains. Usage: @@NAME {[<sql_id>|<sid>|<plan_hash_value>|-f"<filter>"] [YYMMDDHH24MI] [YYMMDDHH24MI]}|{-snap [secs]} [-sid] [-dash] [-flat]
    options:
        -dash: source from dba_hist_active_session_history instead of gv$active_session_history
        -snap <secs> : show wait chain within recent n secs
        -sid:  grouping by sid instead of sql_id
        -phase: show top phase instead of top object
        -op   : show top op name instead of top object
        -p    : show progam + event + p1/2/3 instead of event + top object
        -flat : show ashchain in flat style instead of tree style
This script references Tanel Poder's script
    --[[
        @con : 12.1={AND prior con_id=con_id} default={}
        &tree  : default={1} flat={0}
        &V8    : ash={gv$active_session_history},dash={Dba_Hist_Active_Sess_History}
        &Filter: default={:V1 in(''||session_id,''||sql_plan_hash_value,sql_id,top_level_sql_id,SESSION_ID||'@'||&INST1,event,''||current_obj#)} f={}
        &filter1: default={0} f={1}
        &range : default={sample_time BETWEEN NVL(TO_DATE(NVL(:V2,:STARTTIME),'YYMMDDHH24MI'),SYSDATE-7) AND NVL(TO_DATE(NVL(:V3,:ENDTIME),'YYMMDDHH24MI'),SYSDATE)}, snap={sample_time>=sysdate - nvl(:V1,60)/86400}, f1={}
        &snap:   default={--} snap={}
        &pname : default={decode(session_type,'BACKGROUND',program2)} p={program2}
        &group : default={curr_obj#}, p={p123}, phase={phase} , op={sql_opname}
        &grp1  : default={sql_ids}, sid={sids}
        &grp2  : default={sql_id}, sid={sid}, none={sample_id}
        &unit  : default={1}, dash={10}
        &INST1 : default={inst_id}, dash={instance_number}
        &OBJ   : default={dba_objects}, dash={(select obj# object_id,object_name from dba_hist_seg_stat_obj)}
        @tmodel: 11.2={time_model} default={to_number(null)}
        @opname: 11.2={SQL_OPname,TOP_LEVEL_CALL_NAME} default={null}
        @CHECK_ACCESS_OBJ  : dba_objects={&obj}, default={all_objects}
        @INST: 11.2={'@'|| a.BLOCKING_INST_ID}, default={'@'||a.&inst1}
        @secs: 11.2={round(sum(least(delta_time,nvl(tm_delta_db_time,delta_time)))*1e-6,2) db_time,} default={&unit,}
        @io  : 11.2={DELTA_INTERCONNECT_IO_BYTES} default={null}
        @exec_id:  11.2={CONNECT_BY_ROOT sql_id||nvl(sql_exec_id||to_char(sql_exec_start,'yymmddhh24miss'),session_id||','||&inst1||','||seq#) } default={null}
    --]]
]]*/

col db_time format smhd2
col io format KMG

SET verify off feed off
var target VARCHAR2
var chose varchar2
var filter2 number;

declare
    target varchar2(2000) := q'[select a.*,nvl(&tmodel,0) tmodel,&INST1 inst,SESSION_ID||'@'||&INST1 SID,nullif(a.blocking_session|| &INST,'@') b_sid,sample_time+0 stime from ]'||:V8||' a where '||:range;
    chose varchar2(2000) := '1';
BEGIN
    :filter2 := 1;
    IF (:V1 IS NOT NULL AND :snap IS NOT NULL) OR :filter1=1 THEN
        :filter2 := 0;
        target := replace(replace(q'[select * from (select /*+no_merge*/ distinct stime from (@target and (@filter))) a natural join (@target) b]','@filter',:filter),'@target',target);
        chose := 'CASE WHEN ' ||:filter|| ' THEN 1 ELSE 0 END';
    END IF;
    :target := '('||target||')';
    :chose:= chose;
END;
/

set verify on
var cur refcursor
BEGIN
    IF &tree=0 THEN
        open :cur for
            WITH bclass AS (SELECT class, ROWNUM r from v$waitstat),
            ash_base as &target,
            ash_data AS (SELECT /*+ordered swap_join_inputs(b) swap_join_inputs(c) swap_join_inputs(u)  use_hash(a b u c)  no_expand*/
                        a.*, 
                        nvl2(b.chose,0,1) is_root,
                        u.username,
                        case 
                            when current_obj# > 0 then ''||current_obj# 
                            when p3text='100*mode+namespace' and p3>power(2,32) then ''||trunc(p3/power(2,32))
                            when p3text like '%namespace' then 'x$kglst#'||trunc(mod(p3,power(2,32))/power(2,16))
                            when p1text like 'cache id' then (select max(parameter) from v$rowcache where cache#=p1)
                            when p1text ='file#' and p2text='block#' then 'file#'||p1||' block#'||p2
                            when p3text in('block#','block') then 'file#'||DBMS_UTILITY.DATA_BLOCK_ADDRESS_FILE(p3)||' block#'||DBMS_UTILITY.DATA_BLOCK_ADDRESS_FILE(p3)
                            when p1text ='idn' then 'v$db_object_cache hash#'||p1
                            when a.event like 'latch%' and p2text='number' then (select max(name) from v$latchname where latch#=p2)
                            when c.class is not null then c.class
                            else ''||greatest(current_obj#,-2)
                        end curr_obj#,
                        CASE WHEN a.session_type = 'BACKGROUND' OR REGEXP_LIKE(a.program, '.*\([PJ]\d+\)') THEN
                            regexp_replace(REGEXP_REPLACE(regexp_substr(a.program,'\([^\(]+\)'), '\d\w\w', 'nnn'),'\d','n')
                        ELSE
                            '('||REGEXP_REPLACE(REGEXP_SUBSTR(a.program, '[^@]+'), '\d', 'n')||')'
                        END || ' ' program2,
                        CASE WHEN a.session_state = 'WAITING' THEN a.event 
                             WHEN bitand(tmodel, power(2,18)) > 0 THEN 'CPU: IM Query'
                             WHEN bitand(tmodel, power(2,19)) > 0 THEN 'CPU: IM Populate'
                             WHEN bitand(tmodel, power(2,20)) > 0 THEN 'CPU: IM Prepopulate'
                             WHEN bitand(tmodel, power(2,21)) > 0 THEN 'CPU: IM Repopulate'
                             WHEN bitand(tmodel, power(2,22)) > 0 THEN 'CPU: IM Trickle Repop'
                        ELSE 'ON CPU' END ||
                        CASE WHEN c.class IS NOT NULL THEN ' ['||c.class||']'
                             WHEN a.event IS NULL AND tmodel<power(2,18) THEN nvl2(a.p1text,' ['||trim(p1text||' '||p2text||' '||p3text)||']','')
                        END || ' ' event2,
                        replace(nvl2(p1text,p1text||' #'||case when p1>power(2,32) then to_char(p1,'0XXXXXXXXXXXXXXX') else ''||p1 end,'')
                            ||nvl2(p2text,'/'||p2text||' #'||case when p2>power(2,32) then to_char(p2,'0XXXXXXXXXXXXXXX') else ''||p2 end,'')
                            ||nvl2(p3text,'/'||p3text||' #'
                                || case when p3>power(2,32) then to_char(p3,'0XXXXXXXXXXXXXXX') 
                                        when c.class is not null then c.class
                                        else ''||p3 end,''),'# #',' #') p123,
                        coalesce(trim(decode(bitand(tmodel,power(2, 3)),0,'','in_connection_mgmt ') || 
                            decode(bitand(tmodel,power(2, 4)),0,'','in_parse ') || 
                            decode(bitand(tmodel,power(2, 7)),0,'','in_hard_parse ') || 
                            decode(bitand(tmodel,power(2,10)),0,'','in_sql_execution ') || 
                            decode(bitand(tmodel,power(2,11)),0,'','in_plsql_execution ') || 
                            decode(bitand(tmodel,power(2,12)),0,'','in_plsql_rpc ') || 
                            decode(bitand(tmodel,power(2,13)),0,'','in_plsql_compilation ') || 
                            decode(bitand(tmodel,power(2,14)),0,'','in_java_execution ') || 
                            decode(bitand(tmodel,power(2,15)),0,'','in_bind ') || 
                            decode(bitand(tmodel,power(2,16)),0,'','in_cursor_close ') || 
                            decode(bitand(tmodel,power(2,17)),0,'','in_sequence_load ') || 
                            decode(bitand(tmodel,power(2,18)),0,'','in_inmemory_query ') || 
                            decode(bitand(tmodel,power(2,19)),0,'','in_inmemory_populate ') || 
                            decode(bitand(tmodel,power(2,20)),0,'','in_inmemory_prepopulate ') || 
                            decode(bitand(tmodel,power(2,21)),0,'','in_inmemory_repopulate ') || 
                            decode(bitand(tmodel,power(2,22)),0,'','in_inmemory_trepopulate ') || 
                            decode(bitand(tmodel,power(2,23)),0,'','in_tablespace_encryption ')),&opname) phase
              FROM   ash_base a
              LEFT   JOIN (SELECT DISTINCT b_sid, stime, 0 chose 
                           FROM ash_base WHERE b_sid IS NOT NULL) b
              ON     (a.sid = b.b_sid AND a.stime = b.stime)
              LEFT JOIN dba_users  u 
              ON    (a.user_id = u.user_id)
              LEFT JOIN bclass c
              ON    (a.p3text='class#' and a.p3=c.r)
              WHERE  b.chose IS NOT NULL
              OR     a.b_sid IS NOT NULL),
            chains AS (
                SELECT /*+NO_EXPAND PARALLEL(4)*/
                      level lvl,
                      sid w_sid,
                      SYS_CONNECT_BY_PATH(case when :filter2 = 1 then 1 when &filter then 1 else 0 end ,',') is_found,
                      REPLACE(trim('>' from regexp_replace(SYS_CONNECT_BY_PATH(coalesce(sql_id,top_level_sql_id,program2), '>')||decode(connect_by_isleaf,1,nvl2(b_sid,'>(Idle)','')),'(>.+?)\1+','\1 +',2)), '>', ' > ') sql_ids,
                      REPLACE(trim('>' from regexp_replace(SYS_CONNECT_BY_PATH(&pname ||event2, '>')||decode(connect_by_isleaf,1,nvl2(b_sid,'>(Idle)','')),'(>.+?)\1+','\1 +',2)), '>', ' > ') path, -- there's a reason why I'm doing this (ORA-30004 :)
                      REPLACE(trim('>' from regexp_replace(SYS_CONNECT_BY_PATH(sid,'>')||decode(connect_by_isleaf,1,nullif('>'||b_sid,'>')),'(>.+?)\1+','\1 +')), '>', ' > ') sids,
                      &exec_id sql_exec,
                      CONNECT_BY_ROOT &group root_&group,
                      CONNECT_BY_ISLEAF isleaf,
                      CONNECT_BY_ISCYCLE iscycle,
                      d.*
                FROM  ash_data d
                CONNECT BY NOCYCLE (PRIOR d.b_sid = d.sid AND PRIOR stime = stime &con)
                START WITH is_root=1
            )
            SELECT * FROM (
                SELECT to_char(RATIO_TO_REPORT(COUNT(*)) OVER () * 100,'990.00')||'%' "%This",
                       SUM(&UNIT) AAS,count(distinct sql_exec) execs, &secs sum(&io) io,
                       &snap w_sid, b_sid,
                       root_&group, &grp1, path wait_chain
                FROM   chains c
                WHERE  isleaf = 1 and is_found like '%1%'
                GROUP BY root_&group, path,&grp1 &snap , w_sid, b_sid
                ORDER BY AAS DESC
                )
            WHERE ROWNUM <= 50;
    ELSE
        OPEN :cur FOR
            WITH bclass AS (SELECT class, ROWNUM r from v$waitstat),
            ash_base as &target,
            ash_data AS (SELECT /*+ordered swap_join_inputs(b) swap_join_inputs(c) swap_join_inputs(u)  use_hash(a b u c)  no_expand*/
                        a.*, 
                        nvl2(b.chose,0,1) is_root,
                        u.username,
                        case 
                            when current_obj# > 0 then ''||current_obj# 
                            when p3text='100*mode+namespace' and p3>power(2,32) then ''||trunc(p3/power(2,32))
                            when p3text like '%namespace' then 'x$kglst#'||trunc(mod(p3,power(2,32))/power(2,16))
                            when p1text like 'cache id' then (select max(parameter) from v$rowcache where cache#=p1)
                            when p1text ='idn' then 'v$db_object_cache hash#'||p1
                            when a.event like 'latch%' and p2text='number' then (select max(name) from v$latchname where latch#=p2)
                            when c.class is not null then c.class
                            else ''||greatest(current_obj#,-2)
                        end curr_obj#,
                        CASE WHEN a.session_type = 'BACKGROUND' OR REGEXP_LIKE(a.program, '.*\([PJ]\d+\)') THEN
                            regexp_replace(REGEXP_REPLACE(regexp_substr(a.program,'\([^\(]+\)'), '\d\w\w', 'nnn'),'\d','n')
                        ELSE
                            '('||REGEXP_REPLACE(REGEXP_SUBSTR(a.program, '[^@]+'), '\d', 'n')||')'
                        END || ' ' program2,
                        CASE WHEN a.session_state = 'WAITING' THEN a.event 
                             WHEN bitand(tmodel, power(2,18)) > 0 THEN 'CPU: IM Query'
                             WHEN bitand(tmodel, power(2,19)) > 0 THEN 'CPU: IM Populate'
                             WHEN bitand(tmodel, power(2,20)) > 0 THEN 'CPU: IM Prepopulate'
                             WHEN bitand(tmodel, power(2,21)) > 0 THEN 'CPU: IM Repopulate'
                             WHEN bitand(tmodel, power(2,22)) > 0 THEN 'CPU: IM Trickle Repop'
                        ELSE 'ON CPU' END ||
                        CASE WHEN c.class IS NOT NULL THEN ' ['||c.class||']'
                             WHEN a.event IS NULL AND tmodel<power(2,18) THEN nvl2(a.p1text,' ['||trim(p1text||' '||p2text||' '||p3text)||']','')
                        END || ' ' event2,
                        replace(nvl2(p1text,p1text||' #'||case when p1>power(2,32) then to_char(p1,'0XXXXXXXXXXXXXXX') else ''||p1 end,'')
                            ||nvl2(p2text,'/'||p2text||' #'||case when p2>power(2,32) then to_char(p2,'0XXXXXXXXXXXXXXX') else ''||p2 end,'')
                            ||nvl2(p3text,'/'||p3text||' #'
                                || case when p3>power(2,32) then to_char(p3,'0XXXXXXXXXXXXXXX') 
                                        when c.class is not null then c.class
                                        else ''||p3 end,''),'# #',' #') p123,
                        coalesce(trim(decode(bitand(tmodel,power(2, 3)),0,'','in_connection_mgmt ') || 
                            decode(bitand(tmodel,power(2, 4)),0,'','in_parse ') || 
                            decode(bitand(tmodel,power(2, 7)),0,'','in_hard_parse ') || 
                            decode(bitand(tmodel,power(2,10)),0,'','in_sql_execution ') || 
                            decode(bitand(tmodel,power(2,11)),0,'','in_plsql_execution ') || 
                            decode(bitand(tmodel,power(2,12)),0,'','in_plsql_rpc ') || 
                            decode(bitand(tmodel,power(2,13)),0,'','in_plsql_compilation ') || 
                            decode(bitand(tmodel,power(2,14)),0,'','in_java_execution ') || 
                            decode(bitand(tmodel,power(2,15)),0,'','in_bind ') || 
                            decode(bitand(tmodel,power(2,16)),0,'','in_cursor_close ') || 
                            decode(bitand(tmodel,power(2,17)),0,'','in_sequence_load ') || 
                            decode(bitand(tmodel,power(2,18)),0,'','in_inmemory_query ') || 
                            decode(bitand(tmodel,power(2,19)),0,'','in_inmemory_populate ') || 
                            decode(bitand(tmodel,power(2,20)),0,'','in_inmemory_prepopulate ') || 
                            decode(bitand(tmodel,power(2,21)),0,'','in_inmemory_repopulate ') || 
                            decode(bitand(tmodel,power(2,22)),0,'','in_inmemory_trepopulate ') || 
                            decode(bitand(tmodel,power(2,23)),0,'','in_tablespace_encryption ')),&opname) phase
              FROM   ash_base a
              LEFT   JOIN (SELECT DISTINCT b_sid, stime, 0 chose 
                           FROM ash_base WHERE b_sid IS NOT NULL) b
              ON     (a.sid = b.b_sid AND a.stime = b.stime)
              LEFT JOIN dba_users  u 
              ON    (a.user_id = u.user_id)
              LEFT JOIN bclass c
              ON    (a.p3text='class#' and a.p3=c.r)
              WHERE  b.chose IS NOT NULL
              OR     a.b_sid IS NOT NULL),
            chains AS (
                SELECT /*+NO_EXPAND PARALLEL(4)*/
                       sid w_sid,b_sid,
                       rownum-level r,
                       inst,
                       case when :filter2 = 1 then 1 when &filter then 1 else 0 end is_found,
                       TRIM('>' FROM regexp_replace(SYS_CONNECT_BY_PATH(trim(decode(:grp2,'sample_id','x','sql_id',nvl(sql_id, program2),&grp2)),'>'),'(>.+?)\1+','\1(+)',2)) sql_ids,
                       TRIM('>' FROM regexp_replace(SYS_CONNECT_BY_PATH(trim(&pname || event2), '>'), '(>.+?)\1+', '\1(+)',2)) p, 
                       &exec_id sql_exec,
                       connect_by_isleaf isleaf,
                       CONNECT_BY_ISCYCLE iscycle,
                       CONNECT_BY_ROOT decode(:grp2,'sample_id',trim(&pname || event2),'sql_id',nvl(sql_id, program2),&grp2) root_sql,
                       trim(decode(:grp2,'sample_id',' ','sql_id',nvl(sql_id, program2),&grp2))  sq_id,
                       trim(&pname || event2) env,
                       &group,
                       &io io
                FROM  ash_data d
                CONNECT BY NOCYCLE (PRIOR d.b_sid = d.sid AND PRIOR stime = stime  &con)
                START WITH is_root=1),
            calc AS (
               SELECT /*+materialize*/ * 
               FROM (SELECT a.*,
                            100*aas/sum(aas*decode(lvl,0,1,0)) over() pct,
                            dense_rank() over(order by rnk desc) rnk_ 
                 FROM (
                  SELECT /*+leading(b a)*/
                         sum(count(1)) over(partition by root_sql) rnk,
                         max(nvl2(&group,' ('||grp_count||') '||&group,'')) keep(dense_Rank last order by grp_count) &group,
                         root_sql,
                         sql_ids,
                         trim(p)||idle p,
                         SUM(&UNIT*isleaf) delta,
                         max(nullif(sq_id||plus1,'(+)')) sq_id,
                         max(env||plus2||replace(idle,'>',' > ')) env,
                         COUNT(DISTINCT sql_exec) execs,
                         SUM(&UNIT) aas,
                         sum(io) io,
                         lvl
                  FROM (
                      SELECT A.*,
                             b.is_found,
                             b.rnk,
                             greatest(length(sql_ids)-length(replace(sql_ids,'>')),length(p)-length(replace(p,'>'))) lvl,
                             case when iscycle=0 and isleaf=1 and b_sid is not null then
                                       case when b_sid like '%@'||inst then '>(Unknown)' else '>(Remote)' end
                             end idle,
                             case when sql_ids like '%(+)' then '(+)' end plus1,
                             case when p like '%(+)' then '(+)' end|| decode(iscycle,1,'(C)') plus2,
                             sum(&UNIT) over(partition by sql_ids,p,&group,case when  iscycle=0 and isleaf=1 and b_sid is not null then 1 else 0 end) grp_count
                      FROM   chains a,
                             (SELECT b.*, dense_rank() OVER(ORDER BY leaves DESC,paths) rnk
                              FROM   (SELECT r, MAX(sql_ids) || MAX(p) paths,max(is_found) is_found,COUNT(1) OVER(PARTITION BY MAX(sql_ids) || MAX(p)) leaves 
                                      FROM CHAINS c 
                                      GROUP BY r) b
                              WHERE is_found=1) b
                      WHERE  a.r = b.r
                      AND    b.rnk <= 100) --exclude the chains whose rank >
                  GROUP  BY root_sql, sql_ids, p,idle,lvl) A)
               WHERE rnk_<=10)
            SELECT DECODE(LEVEL, 1, to_char(pct,'fm990.99'), '|'||to_char(least(pct,99.99),'90.00'))||'%' "Pct",
                   AAS,
                   EXECS,
                   DELTA "Leaf|AAS",
                   IO,
                   &group top_&group,
                   DECODE(LEVEL, 1, '', ' |') || LPAD(' ', (LEVEL - 1) * 2 - 1, ' ') || ' ' || SQ_ID WAIT_CHAIN,
                   DECODE(LEVEL, 1, '', ' |') || LPAD(' ', (LEVEL - 1) * 2 - 1, ' ') || ' ' || ENV EVENT_CHAIN,
                   replace(p,'>',' > ') FULL_EVENT_CHAIN
            FROM   calc
            START  WITH LVL = 0
            CONNECT BY NOCYCLE SQL_IDS LIKE PRIOR SQL_IDS || '%'
                AND    P LIKE PRIOR P || '%'
                AND    LVL = PRIOR LVL + 1
            ORDER SIBLINGS BY AAS DESC;
    END IF;
END;
/