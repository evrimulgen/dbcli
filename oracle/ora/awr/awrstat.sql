/*[[Show the AWR performance trend for a specific SQL. Usage: @@NAME <sql_id|plan_hash_value|signature> [-d|-p] [-m]
    -d: Group by day, otherwise group in detail
    -p: Group by plan_hash_value
    -m: Group by signature, otherwise group by sql id
    --[[
        &BASE : s={sql_id}, m={signature}
        &TIM  : t={YYYYMMDD HH24:MI}, d={YYYYMMDD} p={" "}
        &avg  : default={1}, avg={nullif(SUM(GREATEST(exec,parse)),0)}
        @ver  : 11.2={} default={--}
    --]]
]]*/

ORA _sqlstat
col ela,ELA(Avg) format smhd2
col iowait,cpuwait,ccwait,clwait,apwait,plsql for pct1
Col buff,read,write,cellio,oflin,oflout format kmg

select time,sql_id,plan_hash,
       sum(exec)   exec,
       sum(parse)  parse,
       max(vers)  vers,
       count(1)    SEENS,
       sum(ela)    ELA,
       round(sum(ela)/nullif(decode(SUM(exec),0,floor(sum(parse)/greatest(sum(px_count),1)),sum(exec)),0),2) "ELA(Avg)",
       sum(iowait)/sum(ela) iowait,
       sum(cpuwait)/sum(ela) cpuwait,
       sum(ccwait)/sum(ela) ccwait,
       sum(clwait)/sum(ela) clwait,
       sum(apwait)/sum(ela)  apwait,
       sum(plsql)/sum(ela)  plsql,
       round(sum(buff)/&avg,2) buff,
       &ver round(sum(cellio)/&avg,2) cellio, round(sum(oflin)/&avg,2) oflin, round(sum(oflout)/&avg,2) oflout,
       round(sum(read)/&avg,2) read,
       round(sum(write)/&avg,2)  write,
       round(sum(rows#)/&avg,2) rows#,
       round(sum(fetches)/&avg,2) fetches,
       max(px_count) px
FROM(
    select /*+no_expand*/
           to_char(max(tim),'&TIM') time,sql_id,plan_hash,
           sum(exec)   exec,
           sum(parse)  parse,
           max(vers)  vers,
           count(1)    SEENS,
           sum(ela)    ELA,
           sum(iowait) iowait,
           sum(cpuwait) cpuwait,
           sum(ccwait) ccwait,
           sum(clwait) clwait,
           sum(apwait) apwait,
           max(px_count) px_count,
           sum(buff) buff,
           sum(read) read,
           sum(write) write,
           sum(cellio) cellio,
           sum(oflin) oflin,
           sum(oflout) oflout,
           sum(rows#) rows#,
           sum(fetches) fetches,
           sum(PLSQL) PLSQL
    from(
        select a.end_interval_time tim,
               a.sql_id,
               a.plan_hash_value plan_hash,
               a.executions EXEC,
               a.version_count vers,
               a.parse_calls parse,
               nvl(MIN(decode(executions,0,null,snap_id)) OVER(PARTITION BY sql_id,plan_hash_value ORDER BY snap_id RANGE BETWEEN 0 FOLLOWING AND UNBOUNDED FOLLOWING),
                   MAX(decode(parse_calls,0,null,snap_id)) OVER(PARTITION BY sql_id,plan_hash_value ORDER BY snap_id RANGE BETWEEN UNBOUNDED PRECEDING AND 0 PRECEDING)) snap_id,
               round(a.elapsed_time,2) ela,
               ROUND(a.iowait,2) iowait,
               ROUND(a.cpu_time,2) cpuwait,
               ROUND(a.ccwait,2) ccwait,
               ROUND(a.clwait,2) clwait,
               ROUND(a.apwait,2) apwait,
               a.px_servers_execs px_count,
               PLSEXEC_TIME+JAVEXEC_TIME PLSQL,
               cellio,oflin,oflout,
               greatest(disk_reads,phyread) READ,
               nvl(phywrite,direct_writes) WRITE,
               buffer_gets buff,
               a.rows_processed rows#,
               a.fetches
         from &awr$sqlstat  a
        WHERE :V1 in(sql_id,''||plan_hash_value,''||signature))
    group by snap_id,sql_id,plan_hash
    having sum(ela)>0)
 group by time,sql_id,plan_hash
 order by 1 desc