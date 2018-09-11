/*[[Show resource manager plan. Uasage: @@NAME [plan_name|schema_name]
   --[[
       @ALIAS: rsrc
       @ver1: 11.2={MGMT_} default={CPU}
       @ver2: 12.1={PARALLEL_SERVER_LIMIT} default={PARALLEL_TARGET_PERCENTAGE}
       @ver3: 12.1={con_id} default={}
       @ver4: 12.1={} default={--}
       @ver5: {
            12.1={INST_ID,&ver3,NAME PLAN,IS_TOP_PLAN IS_TOP, CPU_MANAGED CPU, INSTANCE_CAGING CAGING, PARALLEL_SERVER_LIMIT PX_LIMIT,
                  PARALLEL_SERVERS_ACTIVE PX_ACTIVE,PARALLEL_SERVERS_TOTAL PX_TOTAL,PARALLEL_EXECUTION_MANAGED PX_CTRL, 
                  DIRECTIVE_TYPE DX,SHARES,UTILIZATION_LIMIT UT, MEMORY_MIN  MEM_MIN, MEMORY_LIMIT MEM_LIMIT,PROFILE}
            default={*}
       }           
}
   ]]--
]]*/
set feed off

col timeout,max_ela,max_idle,max_blkr,CALL_TIME,ALL_TIME for smhd1
col IO_REQs,LIO_req format tmb
col IO_MB,MEM_MIN format kmg
col CPU_TIME,CPU_WAIT,QUEUED_TM,ACT_TM for usmhd1
col px_sess,max_ut for %.0f%%

PRO DBA_RSRC_PLANS
PRO ===============
select * from dba_rsrc_plans;

PRO DBA_RSRC_PLAN_DIRECTIVES
PRO ========================
select nvl2(a.name,'$GREPCOLOR$','')||PLAN plan,
       GROUP_OR_SUBPLAN,TYPE,&ver1.p1 p1,&ver1.p2 p2,&ver1.p3 p3,&ver1.p4 p4,&ver1.p5 p5,&ver1.p6 p6,&ver1.p7 p7,&ver1.p8 p8,
       '|' "|",ACTIVE_SESS_POOL_P1 sess,QUEUEING_P1 timeout,
       '|' "|",&ver2 max_px,PARALLEL_DEGREE_LIMIT_P1 max_dop,PARALLEL_QUEUE_TIMEOUT TIMEOUT,
       &ver4 PARALLEL_STMT_CRITICAL critical,
       '|' "|",MAX_EST_EXEC_TIME max_ela,undo_pool undo,MAX_IDLE_TIME max_idle,MAX_IDLE_BLOCKER_TIME max_blkr,
       &ver4 '|' "|",UTILIZATION_LIMIT MAX_UT,
       '|' "|",SWITCH_GROUP SWITCH_TO, SWITCH_FOR_CALL FOR_CALL,SWITCH_TIME CALL_TIME,
       &ver4 SWITCH_ELAPSED_TIME ALL_TIME,
       SWITCH_IO_MEGABYTES*1024*1024 IO_MB, 
       SWITCH_IO_REQS IO_REQs
       &ver4 ,SWITCH_IO_LOGICAL LIO_req
FROM   (select name from v$rsrc_plan) a,dba_rsrc_plan_directives b
where  b.plan=a.name(+)
ORDER  by nvl2(a.name,1,2),1,2;

PRO GV$RSRC_PLANS
PRO ===============
select &ver5 from gv$rsrc_plan
ORDER BY 1,2;

PRO GV$RSRC_CONSUMER_GROUP
PRO =======================
SELECT INST_ID,REPLACE(NAME,'_ORACLE_BACKGROUND_GROUP_','BACKGROUND@') RSRC_GROUP,ACTIVE_SESSIONS ACT_SSS, EXECUTION_WAITERS WAITERS,
       REQUESTS REQS,QUEUE_LENGTH QUEUES,QUEUED_TIME QUEUED_TM,ACTIVE_SESSIONS_KILLED ACT_KILLS,
       IDLE_SESSIONS_KILLED IDLE_KILLS,IDLE_BLKR_SESSIONS_KILLED BLKR_KILLS,
       '|' "|",
       CONSUMED_CPU_TIME CPU_TIME,CPU_WAIT_TIME CPU_WAIT,CPU_WAITs WAITS, YIELDS ,
       CPU_DECISIONS DECISIONS,CPU_DECISIONS_EXCLUSIVE EXCLUDES, CPU_DECISIONS_WON WONS,
       '|' "|",
       CURRENT_PQS_ACTIVE PX_ACT_STMT,CURRENT_PQ_SERVERS_ACTIVE ACT_SVRS,PQ_ACTIVE_TIME ACT_TM,PQ_SERVERS_USED USED,
       PQS_QUEUED QUEUED,PQ_QUEUED_TIME QUEUED_TM,PQS_COMPLETED COMPLETED
FROM gv$rsrc_consumer_group
ORDER BY 1,2;