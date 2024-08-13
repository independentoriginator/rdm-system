create or replace view v_sys_maintenance_mode
as
select 
	'Liquibase'::text as process_name
	, l.lockgranted as lock_time
	, l.lockedby as locked_by
from 
	${mainSchemaName}.databasechangeloglock l 
where 
	l.locked 
	and extract(day from ${mainSchemaName}.f_current_timestamp() - l.lockgranted) < 1.0
union all
select 
	'Materialized views refreshing'::text as process_name
	, null as lock_time
	, null as locked_by
from 
	${mainSchemaName}.v_meta_view v
where 
	v.is_materialized
	and not v.is_populated
	and not v.is_disabled
limit 1
;

comment on view v_sys_maintenance_mode is 'Признак включения режима обслуживания базы данных';