/*[[Show ash cost for a specific SQL for multiple executions. usage: @@NAME {<sql_id|plan_hash_value> [sql_exec_id] [YYMMDDHH24MI] [YYMMDDHH24MI]}  [-o] [-d|-g]
-o   : Show top object#, otherwise show top event
-d   : Only query dba_hist_active_sess_history
-g   : Only query gv$active_session_history
-all : Use hierachy clause to grab the possible missing PX slave records

--[[
    @adaptive : 12.1={adaptive} default={}
    @phf : 12.1={sql_full_plan_hash_value} default={sql_plan_hash_value}
    @phf2: 12.1={to_char(regexp_substr(other_xml,'plan_hash_full".*?(\d+)',1,1,'n',1))} default={null}
    @con : 12.1={AND prior con_id=con_id} default={}
    &V9  : ash={gv$active_session_history}, dash={Dba_Hist_Active_Sess_History}
    &top1: default={ev}, O={CURR_OBJ#}
    &top2: default={CURR_OBJ#}, O={ev}
    
    &vw  : default={A} G={G} D={D} 
    &Title: default={Objects}, O={Events}
    &titl2: default={Events}, O={Objects}
    &fmt: default={} f={} s={-rows -parallel}
    &simple: default={1} s={0}
    &hierachy: {
        default={1 lv,
                decode(:V1,top_level_sql_id,top_level_sql_id,sql_id) sql_id,
                sql_exec_id sql_exec_id_,
                sql_exec_start sql_exec_start_,
                nvl(sql_plan_hash_value,0) phv1,
                sql_plan_line_id,
                &phf plan_hash_full,
                decode(:V1,sql_id,1,top_level_sql_id,2,3) pred_flag} 
           all={level lv,
                connect_by_root(decode(:V1,top_level_sql_id,top_level_sql_id,sql_id)) sql_id,
                connect_by_root(sql_exec_id) sql_exec_id_,
                connect_by_root(sql_exec_start) sql_exec_start_,
                coalesce(nullif(sql_plan_hash_value,0),connect_by_root(sql_plan_hash_value),0) phv1,
                coalesce(nullif(case when sql_plan_line_id>65535 then 0 else sql_plan_line_id end,0),connect_by_root(sql_plan_line_id),0) sql_plan_line_id,
                coalesce(nullif(&phf,0),connect_by_root(&phf),0) plan_hash_full,
                connect_by_root(decode(:V1,sql_id,1,top_level_sql_id,2,3)) pred_flag}
    }
    &public: {default={ aas_,
                        dbid,
                        instance_number inst_id,
                        nvl(qc_instance_id,instance_number) qc_inst,
                        session_id SID,
                        nvl(qc_session_id,session_id) qc_sid,
                        current_obj#,
                        p1,
                        p2,
                        p3,
                        p1text,
                        p2text,
                        p3text,
                        event,
                        wait_class,
                        tm_delta_time,
                        tm_delta_db_time,
                        delta_time,
                        DELTA_READ_IO_REQUESTS,DELTA_WRITE_IO_REQUESTS,DELTA_INTERCONNECT_IO_BYTES,
                        IN_PLSQL_EXECUTION,IN_PLSQL_RPC,IN_PLSQL_COMPILATION,IN_JAVA_EXECUTION,DECODE(IS_SQLID_CURRENT,'Y','N','Y') IS_NOT_CURRENT,
                        sample_time,
                        sample_id,
                        px_flags,
                        trim(decode(bitand(time_model,power(2, 3)),0,'','connection_mgmt ') || 
                             decode(bitand(time_model,power(2, 4)),0,'','parse ') || 
                             decode(bitand(time_model,power(2, 7)),0,'','hard_parse ') || 
                             decode(bitand(time_model,power(2,15)),0,'','bind ') || 
                             decode(bitand(time_model,power(2,16)),0,'','cursor_close ') || 
                             decode(bitand(time_model,power(2,17)),0,'','sequence_load ') || 
                             decode(bitand(time_model,power(2,18)),0,'','inmemory_query ') || 
                             decode(bitand(time_model,power(2,19)),0,'','inmemory_populate ') || 
                             decode(bitand(time_model,power(2,20)),0,'','inmemory_prepopulate ') || 
                             decode(bitand(time_model,power(2,21)),0,'','inmemory_repopulate ') || 
                             decode(bitand(time_model,power(2,22)),0,'','inmemory_trepopulate ') || 
                             decode(bitand(time_model,power(2,23)),0,'','tablespace_encryption ')) time_model,
                        decode(is_sqlid_current,'N',pga_allocated) pga_,
                        decode(is_sqlid_current,'N',temp_space_allocated) temp_,
                        nvl(trunc(px_flags / 2097152),0) dop_}
    }

    &swcb : {
        default={
            AND     :V1 IN(sql_id,top_level_sql_id,''||sql_plan_hash_value,''||&phf)
            AND     nvl(sql_exec_id,0) = coalesce(0+:v2,sql_exec_id,0)
        }
        all={
            START  WITH :V1 IN(sql_id,top_level_sql_id,''||sql_plan_hash_value,''||&phf)
            CONNECT BY PRIOR sample_time + 0 = sample_time+0
                AND    PRIOR dbid = dbid
                AND    PRIOR session_id=qc_session_id
                AND    PRIOR instance_number=nvl(qc_instance_id,instance_number)
                AND    NOT (session_id=qc_session_id and instance_number=nvl(qc_instance_id,instance_number))
                &con
                AND    LEVEL <3}
    }
--]]
]]*/
set feed off printsize 10000 pipequery off

WITH ALL_PLANS AS 
 (SELECT    id,
            parent_id,
            child_number    ha,
            1               flag,
            TIMESTAMP       tm,
            child_number,
            sql_id,
            nvl(plan_hash_value,0) phv,
            inst_id,
            object#,
            object_name,
            &phf2+0 plan_hash_full
    FROM    gv$sql_plan a
    WHERE   '&vw' IN('A','G')
    AND     :V1 in(''||a.plan_hash_value,sql_id)
    UNION ALL
    SELECT  id,
            parent_id,
            plan_hash_value,
            2,
            TIMESTAMP,
            NULL child_number,
            sql_id,
            nvl(plan_hash_value,0),
            dbid,
            object#,
            object_name,
            &phf2+0 plan_hash_full
    FROM    dba_hist_sql_plan a
    WHERE   '&vw' IN('A','D')
    AND     :V1 in(''||a.plan_hash_value,sql_id)),
plan_objs AS
 (SELECT DISTINCT OBJECT#,OBJECT_NAME FROM ALL_PLANS),
sql_plan_data AS
 (SELECT * FROM
     (SELECT a.*,
             nvl(max(plan_hash_full) over(PARTITION by phv),phv) phf,
             dense_rank() OVER(PARTITION BY phv ORDER BY flag, tm DESC, child_number DESC NULLS FIRST, inst_id desc) seq
      FROM   ALL_PLANS a)
  WHERE  seq = 1),
ash_raw as (
    select h.*,
            nvl(event,'ON CPU') ev,
            nvl(trim(case 
                    when current_obj# > 0 then 
                        nvl((select max(object_name) from plan_objs where object#=current_obj#),''||current_obj#) 
                    when p3text='100*mode+namespace' and p3>power(2,32) then 
                        nvl((select max(object_name) from plan_objs where object#=trunc(p3/power(2,32))),''||trunc(p3/power(2,32))) 
                    when p3text like '%namespace' then 
                        'X$KGLST#'||trunc(mod(p3,power(2,32))/power(2,16))
                    when p1text like 'cache id' then 
                        (select parameter from v$rowcache where cache#=p1 and rownum<2)
                    when event like 'latch%' and p2text='number' then 
                        (select name from v$latchname where latch#=p2 and rownum<2)
                    when p3text='class#' then
                        (select class from (SELECT class, ROWNUM r from v$waitstat) where r=p3 and rownum<2)
                    when px_flags > 65536 then
                        decode(trunc(mod(px_flags/65536, 32)),
                               1,'[PX]Executing-Parent-DFO',     
                               2,'[PX]Executing-Child-DFO',
                               3,'[PX]Sampling-Child-DFO',
                               4,'[PX]Joining-Group',      
                               5,'[QC]Scheduling-Child-DFO',
                               6,'[QC]Scheduling-Parent-DFO',
                               7,'[QC]Initializing-Objects', 
                               8,'[QC]Flushing-Objects',    
                               9,'[QC]Allocating-Slaves', 
                              10,'[QC]Initializing-Granules', 
                              11,'[PX]Parsing-Cursor',   
                              12,'[PX]Executing-Cursor',    
                              13,'[PX]Preparing-Transaction',    
                              14,'[PX]Joining-Transaction',  
                              15,'[PX]Load-Commit', 
                              16,'[PX]Aborting-Transaction',
                              17,'[QC]Executing-Child-DFO',
                              18,'[QC]Executing-Parent-DFO')
                    when time_model is not null then
                        '['||time_model||']'
                    when current_obj#=0 then 'Undo'
                    --when p1text ='idn' then 'v$db_object_cache hash#'||p1
                    --when c.class is not null then c.class
                end),''||greatest(-1,current_obj#)) curr_obj#,
            nvl(wait_class,'ON CPU') wl,
            decode(sec_seq,1,aas) cost,
            nvl(nullif(plan_hash_full,0),phv1) phf,
            decode(sec_seq,1,least(coalesce(tm_delta_db_time,delta_time,AAS*1e6),coalesce(tm_delta_time,delta_time,AAS*1e6),AAS*2e6) * 1e-6) secs,
            case when pred_flag=2 or (is_px_slave=1 and lv=1)
                 then sql_exec_id||',@'||qc_inst||','||qc_sid
                 else sql_exec_id||',@'||qc_inst||','||qc_sid||','||to_char(sql_exec_start,'yyyymmddhh24miss') 
            end sql_exec,
            max(case when pred_flag!=2 or is_px_slave=1 then dop_ end)  over(partition by dbid,phv1,sql_exec_id,pid) dop,
            sum(case when p3text='block cnt' and nvl(event,'temp') like '%temp' then temp_ end) over(partition by dbid,phv1,sql_exec_id,pid,sample_time+0) temp,
            sum(pga_)  over(partition by dbid,phv1,sql_exec_id,pid,sample_time+0) pga
    FROM   (SELECT /*+no_expand opt_param('_optimizer_connect_by_combine_sw', 'false')*/ --PQ_CONCURRENT_UNION 
                   a.*, --seq: if ASH and DASH have the same record, then use ASH as the standard
                   decode(AAS_,1,1,decode((
                        select sign(sum(elapsed_time_delta)/greatest(1,sum(greatest(parse_calls_delta,executions_delta)))-5e6) 
                        from dba_hist_sqlstat b 
                        where a.dbid=b.dbid 
                        and   a.sql_id=b.sql_id and b.plan_hash_value=a.phv1),1,10,1)) AAS,
                   row_number() OVER(PARTITION BY dbid,sample_id,inst_id,sid ORDER BY AAS_,lv desc) seq,
                   --sec_seq: multiple PX processes at the same second wille be treated as on second 
                   row_number() OVER(PARTITION BY dbid,phv1,sql_plan_line_id,sample_time+0,qc_inst,qc_sid ORDER BY AAS_,tm_delta_db_time desc) sec_seq,
                   nvl(decode(pred_flag,2,0,case when sql_plan_line_id>65535 then 0 else sql_plan_line_id end),0) pid,
                   decode(pred_flag,2,0,sql_exec_id_) sql_exec_id,
                   decode(pred_flag,2,SYSDATE,sql_exec_start_) sql_exec_start,
                   case when (qc_sid!=sid or qc_inst!=inst_id) then 1 else 0 end is_px_slave,
                   CASE WHEN 'Y' IN(decode(pred_flag,2,'Y','N'),IN_PLSQL_EXECUTION,IN_PLSQL_RPC,IN_PLSQL_COMPILATION,IN_JAVA_EXECUTION) THEN 1 END IN_PLSQL       
            FROM   (
                SELECT  /*+QB_NAME(ASH) no_merge(a) CONNECT_BY_FILTERING NO_PX_JOIN_FILTER*/
                        &public,
                        &hierachy
                FROM    (
                    select a.*,(select dbid from v$database) dbid,inst_id instance_number,1 aas_
                    from   gv$active_session_history a
                    where  sample_time+0 BETWEEN nvl(to_date(nvl(:V3,:STARTTIME),'YYMMDDHH24MISS'),SYSDATE-7) 
                                         AND     nvl(to_date(nvl(:V4,:ENDTIME),'YYMMDDHH24MISS'),SYSDATE)
                    and   (:V1 IN(sql_id,top_level_sql_id,''||sql_plan_hash_value,''||&phf) or 
                            qc_session_id!=session_id or qc_instance_id!=inst_id or session_serial# != qc_session_serial#                            
                           )) a
                where  '&vw' IN('A','G')
                &swcb
                UNION ALL
                SELECT  /*+QB_NAME(DASH) no_merge(d) CONNECT_BY_FILTERING*/
                        &public,
                        &hierachy
                FROM    (select d.*, 10 aas_ from dba_hist_active_sess_history d) d
                WHERE   '&vw' IN('A','D')
                AND     sample_time+0 BETWEEN nvl(to_date(nvl(:V3,:STARTTIME),'YYMMDDHH24MISS'),SYSDATE-7) 
                                          AND nvl(to_date(nvl(:V4,:ENDTIME),'YYMMDDHH24MISS'),SYSDATE)
                &swcb) a) h
    WHERE  seq = 1),
ash_phv_agg as(
    SELECT  /*+materialize*/ a.* 
    from (
        select  phv phv1,
                nvl(b.phf,a.phf) phfv,
                100*sum(cost) over(partition by nvl(b.phf,a.phf))/sum(cost) over() phf_rate,
                100*ratio_to_report(cost) over() phv_rate,
                first_value(phv) OVER(PARTITION BY nvl(b.phf,a.phf) ORDER BY nvl2(b.phf,0,1),cost desc,aas DESC) phv,
                listagg(phv,',') WITHIN GROUP(ORDER BY cost desc,aas DESC) OVER(PARTITION BY nvl(b.phf,a.phf)) phvs,
                count(1) over(partition by  nvl(b.phf,a.phf)) phv_cnt,
                max(nvl2(b.phf,1,0)) over(partition by  nvl(b.phf,a.phf)) plan_exists
        from (SELECT phv1 phv,max(phf) phf,sum(cost) cost,sum(aas) aas from ash_raw group by phv1) a 
        left join (select distinct phv,phf from sql_plan_data) b using(phv)) A
    WHERE phv_rate>=0.1),
hierarchy_data AS
 (SELECT id, parent_id, phv
  FROM   (select * from sql_plan_data where phv in(select phv from ash_phv_agg where plan_exists=1))
  START  WITH id = 0
  CONNECT BY PRIOR id = parent_id AND phv=PRIOR phv 
  ORDER  SIBLINGS BY id DESC),
ordered_hierarchy_data AS
 (SELECT id,
         parent_id AS pid,
         phv AS phv,
         row_number() over(PARTITION BY phv ORDER BY rownum DESC) AS OID,
         MAX(id) over(PARTITION BY phv) AS maxid
  FROM   hierarchy_data),
qry AS
 ( SELECT DISTINCT sql_id sq,
         flag flag,
         'BASIC ROWS PARTITION PARALLEL PREDICATE NOTE REMOTE &adaptive &fmt' format,
         phv phv,
         coalesce(child_number, 0) child_number,
         inst_id
  FROM   sql_plan_data
  WHERE  phv in(select phv from ash_phv_agg where plan_exists=1)),
xplan AS
 (  SELECT phv,rownum r,a.*
    FROM   qry, TABLE(dbms_xplan.display('dba_hist_sql_plan',NULL,format,'dbid='||inst_id||' and plan_hash_value=' || phv || ' and sql_id=''' || sq ||'''')) a
    WHERE  flag = 2
    UNION ALL
    SELECT phv,rownum,a.*
    FROM   qry,
            TABLE(dbms_xplan.display('gv$sql_plan',NULL,format,'inst_id='|| inst_id||' and plan_hash_value=' || phv || ' and sql_id=''' || sq ||''' and child_number='||child_number)) a
    WHERE  flag = 1),
ash_agg as(
    SELECT /*+materialize*/ 
           a.*, 
           nvl2(costs,trim(dbms_xplan.format_number(costs))||'('||to_char(ratio,case when ratio=10 then '990' else 'fm990.0' end)||'%)','') cost_rate,
           trim(dbms_xplan.format_number(aas)) aas_text,
           trim(dbms_xplan.format_number(io_reqs_/execs)) io_reqs,
           trim(dbms_xplan.format_size(io_bytes_/execs)) io_bytes,
           trim(dbms_xplan.format_size(pga_)) pga,
           trim(dbms_xplan.format_size(temp_)) temp,
           decode(nvl(secs_,0),0,' ',regexp_replace(trim(dbms_xplan.format_time_s(secs_)),'^00:')) secs
    FROM (
        SELECT A.*, first_value('['||lpad(round(100*AAS/aas1,1),4)||'%] '||grp) 
                   OVER(PARTITION BY phv,subtype,sub ORDER BY decode(grp,'-1',1,null,2,0),aas DESC,decode(grp,'ON CPU','Z',grp)) top_grp, 
               listagg(CASE WHEN seq<=5 AND sub IS NOT NULL THEN sub||'('||round(100*AAS/aas0,1)||'%)' END,' / ') 
                   WITHIN GROUP(ORDER BY seq) OVER(PARTITION BY phv,grp,subtype)  top_list,
               round(100*ratio_to_report(costs) over(partition by decode(g,8,null,phv),gid,g,subtype),1) ratio,
               decode(g,8,phv_rate,round(100*ratio_to_report(aas) over(partition by phv,gid,g,subtype),1)) aas_rate
        FROM (
            SELECT A.*,
                max(aas) over(partition by phv,grp) aas0,
                MAX(aas) OVER(PARTITION BY phv,sub,subtype) aas1,
                row_number() OVER(PARTITION BY phv,gid,grp,subtype order by aas desc,sub) seq
            FROM(
                select --+ NO_EXPAND_GSET_TO_UNION NO_USE_DAGG_UNION_ALL_GSETS
                grouping_id(phv1,pid,top2) gid,
                CASE
                    WHEN grouping_id(phv1,top1) =1 THEN 8
                    WHEN grouping_id(pid,top1) =1 THEN 4
                    WHEN grouping_id(top1,pid) =1 THEN 2   
                    WHEN grouping_id(top1,top2) =1 THEN 1
                END g,
                grouping_id(phv1,top1) g1,
                grouping_id(pid,top1) g2,
                grouping_id(top1,top2) g3,
                decode(grouping_id(phv1, pid,top2),3,''||phv1,5,top1,top1) grp,
                decode(grouping_id(phv1, pid,top2),3,top1,5,''||pid,top2) sub,
                DECODE(grouping_id(phv1, pid,top2),3,'E',5,'P','O') subtype,
                phv,phv1,phvs,phfv,plan_exists, top1, top2,pid id,sql_id,
                max(phf_rate) phf_rate,max(phv_rate) phv_rate,max(pred_flag) pred_flag,
                max(dop) max_dop,min(nullif(dop,0)) min_dop,
                COUNT(DISTINCT SQL_EXEC) EXECS,
                SUM(secs) secs_,
                SUM(AAS) AAS,
                sum(cost) costs,
                round(SUM(DECODE(wl, 'ON CPU', AAS, 0))*100/ SUM(AAS), 1) "CPU",
                round(SUM(CASE WHEN wl IN ('User I/O','System I/O') THEN AAS ELSE 0 END) * 100 / SUM(AAS), 1) "IO",
                round(SUM(DECODE(wl, 'Cluster', AAS, 0)) * 100 / SUM(AAS), 1) "CL",
                round(SUM(DECODE(wl, 'Concurrency', AAS, 0)) * 100 / SUM(AAS), 1) "CC",
                round(SUM(DECODE(wl, 'Appidcation', AAS, 0)) * 100 / SUM(AAS), 1) "APP",
                round(SUM(DECODE(wl, 'Scheduler', AAS, 0)) * 100 / SUM(AAS), 1) "SCH",
                round(SUM(DECODE(wl, 'Administrative', AAS, 0)) * 100 / SUM(AAS), 1) "ADM",
                round(SUM(DECODE(wl, 'Configuration', AAS, 0)) * 100 / SUM(AAS), 1) "CFG",
                round(SUM(DECODE(wl, 'Network', AAS, 0)) * 100 / SUM(AAS), 1) "NET",
                round(SUM(CASE WHEN wl IN ('Idle','Commit','Other','Queueing') THEN AAS ELSE 0 END) * 100 / SUM(AAS), 1) oth,
                round(SUM(IN_PLSQL*AAS)* 100 / SUM(AAS), 1) PLSQL,
                SUM(DELTA_READ_IO_REQUESTS+DELTA_WRITE_IO_REQUESTS) io_reqs_,
                SUM(DELTA_INTERCONNECT_IO_BYTES) io_bytes_,
                max(pga) pga_,
                max(temp) temp_,
                min(sample_time) begin_time,
                max(sample_time) end_time
            from (select a.*, nvl(''||&top1,' ') top1,nvl(''||&top2,' ') top2
                  FROM (select /*+ordered use_hash(b)*/ * from ash_phv_agg a natural join ash_raw b) A
                 )
            group by phv,phvs,phvs,phfv,plan_exists,grouping sets((phv1,sql_id),pid,top1,(phv1,top1,sql_id),(pid,top1),(top1,top2))) A) A
    ) a WHERE g IS NOT NULL
),
plan_agg as(
    SELECT decode(plan_exists,1,'*',' ')||phv1 phv2,
           row_number() over(order by phf_rate desc,costs desc,aas desc) r,
           a.* 
    FROM ash_agg a WHERE g=8
),
plan_wait_agg as(
    select rownum r,a.* 
    from (
        SELECT * FROM ash_agg NATURAL JOIN (SELECT phv,top1,replace(top_list,' / ',', ') top_lines FROM ash_agg WHERE SUBTYPE='P' AND seq=1) 
        WHERE GID=7 AND G=2 AND plan_exists=1
        ORDER BY phv,nvl(ratio,aas_rate) DESC,aas desc,top1) a
),
plan_line_agg AS(
    SELECT /*+materialize no_expand no_merge(a) no_merge(b)*/*
    FROM   ordered_hierarchy_data a
    LEFT   JOIN (select a.* from ash_agg a where g=4 and plan_exists=1) b
    USING  (PHV,ID)),
plan_line_xplan AS
 (SELECT /*+no_merge(x) use_hash(x o)*/
       r,
       x.phv phv,
       x.plan_table_output AS plan_output,
       x.id,x.prefix,
       o.pid,o.oid,o.maxid,
       cpu,io,cc,cl,app,oth,adm,cfg,sch,net,plsql,costs,aas_text,execs,
       nvl(cost_rate,' ') cost_rate,
       secs,o.min_dop,o.max_dop,o.io_reqs,o.io_bytes,o.pga,o.temp,
       nvl(top_grp,' ') top_grp,
       '| Plan Hash Value(Full): '||max(phfv) over(partition by x.phv)
       ||decode(min(min_dop) over(partition by x.phv),
               null,'',
               max(max_dop) over(partition by x.phv),'    DoP: '||max(max_dop) over(partition by x.phv),
               '    DoP: '||min(min_dop) over(partition by x.phv)||'-'||max(max_dop) over(partition by x.phv))
       ||'    Period: ['||to_char(min(begin_time) over(partition by x.phv),'yyyy/mm/dd hh24:mi:ss') ||' -- '
            ||to_char(min(end_time) over(partition by x.phv),'yyyy/mm/dd hh24:mi:ss')||']' time_range,
       '| Plan Hash Value(s)   : '||max(phvs) over(partition by x.phv) phvs
  FROM  (SELECT x.*,
                nvl(regexp_substr(prefix,'\d+')+0,least(-1,r-MIN(nvl2(regexp_substr(prefix,'\d+'),r,NULL)) OVER(PARTITION BY phv))) ID
         FROM   (select x.*,regexp_substr(x.plan_table_output, '^\|[-\* ]*([0-9]+|Id) +\|') prefix from xplan x) x) x
  LEFT OUTER JOIN plan_line_agg o
  ON   x.phv = o.phv AND x.id = o.id),

agg_data as(
  select 'line' flag,phv,r,id,''||oid oid,'' full_hash,
         ''||secs secs,''||cost_rate cost_rate,aas_text aas,''||costs costs,''||execs execs,decode(min_dop,null,'',max_dop,''||max_dop,min_dop||'-'||max_dop) dop,
         ''||cpu cpu,''||io io,''||cl cl,''||cc cc,''||app app,''||adm adm,''||cfg cfg,''||sch sch,''||net net,''||oth oth,''||plsql  plsql,io_reqs ioreqs,io_bytes iobytes,pga,temp,
         decode(&simple,1,top_grp) top_list,'' top_list2
  FROM plan_line_xplan
  UNION ALL
  select 'phv' flag,-1,r,rid,''||phv2 oid,decode(pred_flag,3,sql_id,''||phfv),
         ''||secs secs,''|| cost_rate,aas_text aas,''||costs costs,''||execs execs,decode(min_dop,null,'',max_dop,''||max_dop,min_dop||'-'||max_dop) dop,
         ''||cpu cpu,''||io io,''||cl cl,''||cc cc,''||app app,''||adm adm,''||cfg cfg,''||sch sch,''||net net,''||oth oth,''||plsql  plsql,io_reqs,io_bytes,pga,temp,
         ''||top_list,''
  FROM  plan_agg a,(select rownum-3 rid from dual connect by rownum<=3)
  UNION ALL
  select 'wait' flag,phv,r,rid,''||top1 oid,'' phfv,
         ''||secs secs,''|| cost_rate,aas_text aas,''||costs costs,''||execs execs,decode(min_dop,null,'',max_dop,''||max_dop,min_dop||'-'||max_dop) dop,
         '' cpu,'' io,'' cl,'' cc,'' app,'' adm,'' cfg,'' sch,'' net,'' oth,''  plsql,io_reqs,io_bytes,pga,temp,
         ''||top_list,''||top_lines
  FROM  plan_wait_agg a,(select rownum-3 rid from dual connect by rownum<=3)
),

plan_line_widths AS(
    SELECT a.*,swait+swait2+sdop+ csize + rate_size + ssec + sexe + saas + scpu + sio + scl + scc + sapp + ssch +scfg + sadm + snet + soth + splsql + sioreqs + siobytes +spga +stemp + 5 widths
    FROM( 
       SELECT  flag,phv,
               nvl(greatest(max(length(oid)) + 1, 6),0) as csize,
               nvl(greatest(max(length(trim(nullif(full_hash,oid)))), 11),0) as shash,
               nvl(greatest(max(length(trim(secs)))+1, 8),0)*&simple as ssec,
               nvl(greatest(max(length(trim(cost_rate))) + 1, 7),0) as rate_size,
               nvl(greatest(max(length(nullif(aas,costs)))+1,7),0) as saas,
               nvl(greatest(max(length(nullif(execs,'0'))) + 1, 5),0) as sexe,
               nvl(greatest(max(length(nullif(dop,'0'))) + 2, 5),0) as sdop,
               nvl(greatest(max(length(nullif(CPU,'0'))) + 1, 5),0) as scpu,
               nvl(greatest(max(length(nullif(io,'0'))) + 1, 5),0) as sio,
               nvl(greatest(max(length(nullif(cl,'0'))) + 1, 5),0) as scl,
               nvl(greatest(max(length(nullif(cc,'0'))) + 1, 5),0) as scc,
               nvl(greatest(max(length(nullif(app,'0'))) + 1, 5),0) as sapp,
               nvl(greatest(max(length(nullif(adm,'0'))) + 1, 5),0) as sadm,
               nvl(greatest(max(length(nullif(cfg,'0'))) + 1, 5),0) as scfg,
               nvl(greatest(max(length(nullif(sch,'0'))) + 1, 5),0) as ssch,
               nvl(greatest(max(length(nullif(net,'0'))) + 1, 5),0) as snet,
               nvl(greatest(max(length(nullif(oth,'0'))) + 1, 5),0) as soth,
               nvl(greatest(max(length(nullif(plsql,'0'))) + 2, 6),0) as splsql,
               nvl(greatest(max(length(nullif(ioreqs,'0'))) + 1, 8),0)*&simple as sioreqs,
               nvl(greatest(max(length(nullif(iobytes,'0'))) + 1, 9),0)*&simple as siobytes,
               nvl(greatest(max(length(nullif(pga,'0'))) + 1, 5),0)*&simple as spga,
               nvl(greatest(max(length(nullif(temp,'0'))) + 2, 6),0)*&simple as stemp,
               nvl(greatest(max(length(trim(top_list))) + 2, 10),0) as swait,
               nvl(greatest(max(length(trim(top_list2))) + 2, 10),0) as swait2
         FROM  agg_data
         GROUP BY flag,phv) a),
format_info as (
    SELECT flag,phv,r,widths,id,
       decode(id,
            -2,decode(flag,'line',lpad('Ord', csize),'phv','|'||lpad('Plan Hash',csize),'|'||rpad('&titl2',csize)) || lpad('Full Hash', shash) || ' |'
                || lpad('DoP  ', sdop)|| lpad('Execs', sexe) || lpad('Secs', rate_size) || lpad('AAS', saas) || lpad('DB-Time', ssec) 
                || nullif('|'||lpad('CPU%', scpu)  || lpad('IO%', sio) || lpad('CL%', scl) || lpad('CC%', scc) || lpad('APP%', sapp)
                             ||lpad('Sch%', ssch)  || lpad('Cfg%', scfg) || lpad('Adm%', sadm)|| lpad('Net%', snet)
                             ||lpad('OTH%', soth)  || lpad('PLSQL', splsql),'|')
                || nullif('|'||lpad('IO-Reqs',sioreqs)||lpad('IO-Bytes',siobytes)||lpad('PGA',spga)||lpad(' Temp',stemp),'|')
                || nullif('|'||rpad(' Top Lines', swait2),'|') || nullif('|'||rpad(' Top '||decode(flag,'wait','&Title','&titl2'), swait),'|')||'|',
            -1, '+'||lpad('-',csize+shash+1,'-')||'+'
                ||lpad('-',sdop+sexe+rate_size+saas+ssec,'-')
                ||nullif('+'||lpad('-',scpu+sio+scl+scc+sapp+ssch+scfg+sadm+snet+soth+splsql,'-'),'+')
                ||nullif('+'||lpad('-',sioreqs+siobytes+spga+stemp,'-'),'+')
                ||nullif('+'||rpad('-', swait2,'-'),'+') ||nullif('+'||lpad('-',swait,'-'),'+')||'+', 
           decode(flag,'line',lpad(oid, csize),'|'||rpad(oid,csize)) || lpad(nvl(full_hash,' '), shash) || ' |'
                ||lpad(dop||'  ', sdop)||lpad(nvl(execs,' '), sexe) || lpad(nvl(cost_rate,' '), rate_size) || lpad(nvl(aas,' '), saas) || lpad(nvl(secs,' '), ssec) 
                ||nullif('|'||lpad(nvl(CPU,' '), scpu) || lpad(nvl(io,' '), sio) || lpad(nvl(cl,' '), scl) || lpad(nvl(cc,' '), scc) || lpad(nvl(app,' '), sapp)
                            ||lpad(nvl(sch,' '), ssch) || lpad(nvl(cfg,' '), scfg) || lpad(nvl(adm,' '), sadm)|| lpad(nvl(net,' '), snet)
                            ||lpad(nvl(oth,' '), soth)  || lpad(nvl(plsql,' '), splsql),'|')
                ||nullif('|'||lpad(ioreqs||' ',sioreqs)||lpad(iobytes||' ',siobytes)||lpad(nvl(pga,' '),spga)||lpad(nvl(temp,' '),stemp),'|')
                ||nullif('|'||rpad(' '||top_list2, swait2),'|')||nullif('|'||rpad(' ' || top_list, swait),'|')||'|'
            ) fmt
    FROM   plan_line_widths JOIN agg_data USING (flag,phv)
),

plan_output AS (
    SELECT /*+ordered use_hash(b)*/
           phv,
           r,
           b.ID,
           prefix,
           prefix || 
           CASE
               WHEN plan_output LIKE '---------%' THEN
                   rpad('-', widths, '-')
               WHEN b.id = -2 OR b.id > -1 THEN
                   fmt
               WHEN b.id = -4 THEN
                   phvs
               WHEN b.id = -5 THEN
                   time_range
           END || CASE WHEN b.id not in(-4,-5) THEN substr(plan_output, nvl(LENGTH(prefix), 0) + 1) END plan_line
    FROM   (select * from format_info where flag='line') a
    JOIN   plan_line_xplan b USING  (phv,r)
    WHERE  b.id>=-5 and (b.id!=-1 or b.id=-1 and trim(plan_output) is not null)
    ORDER  BY phv, r),
titles as(select distinct phv,fmt,id,flag from format_info where id<0),
final_output as(
    SELECT 0 id,-1 phv,fmt,0 r,0 seq from titles where id=-1 and flag='phv'
    union all
    SELECT 1,-1,fmt,0,0 from titles where id=-2 and flag='phv'
    union all
    SELECT 2,-1,fmt,0,0 from titles where id=-1 and flag='phv'
    UNION ALL
    SELECT 3,-1,fmt,r,0 seq from format_info WHERE flag='phv' and id=0
    UNION ALL
    SELECT 4,-1,fmt,0,0 from titles where id=-1 and flag='phv'
    UNION ALL
    SELECT 5,b.phv,b.plan_output,r,seq
    FROM   (select r,phv1 phv from plan_agg) a,
        (SELECT b.*,rownum seq 
            FROM (
                SELECT phv,null plan_output FROM plan_output group by phv
                UNION ALL
                SELECT phv,rpad('=',max(length(rtrim(plan_line))),'=') FROM plan_output group by phv
                UNION ALL
                SELECT phv,rtrim(plan_line) FROM plan_output

                UNION ALL
                SELECT phv,fmt from titles where id=-1 and flag='wait'
                union all
                SELECT phv,fmt from titles where id=-2 and flag='wait'
                union all
                SELECT phv,fmt from titles where id=-1 and flag='wait'
                UNION ALL
                SELECT * FROM (SELECT phv,fmt from format_info WHERE flag='wait' and id=0 ORDER BY r)
                UNION ALL
                SELECT phv,fmt from titles where id=-1 and flag='wait'
            ) b) b
    WHERE a.phv=b.phv)
select fmt from final_output order by id,r,seq;