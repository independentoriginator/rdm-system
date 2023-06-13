create or replace view v_sys_blocked_activity
as
select 
	waiting_lock.pid
	, blocked_activity.datname as db_name
	, blocked_activity.usename as user_name
	, blocked_activity.query
	, blocking_pid.pid as blocking_pid
	, blocking_activity.usename as blocking_user_name
	, blocking_activity.query as blocking_query
	, blocked_activity.state 
	, blocked_activity.query_start 
	, blocked_activity.state_change
	, blocked_activity.wait_event_type
	, blocked_activity.wait_event
from 
	pg_catalog.pg_locks waiting_lock 
join pg_catalog.pg_stat_activity blocked_activity 
	on blocked_activity.pid = waiting_lock.pid
join lateral (
	select unnest(pg_catalog.pg_blocking_pids(waiting_lock.pid))
) as blocking_pid(pid)
	on true
join pg_catalog.pg_stat_activity blocking_activity 
	on blocking_activity.pid = blocking_pid.pid
where 
	not waiting_lock.granted