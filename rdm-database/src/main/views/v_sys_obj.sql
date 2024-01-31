create or replace view v_sys_obj
as
select 
	c.oid as obj_id
	, c.relname::text as obj_name
	, n.nspname as obj_schema
	, n.nspname || '.' || c.relname as obj_full_name
	, c.relkind as obj_type
	, 'relation'::name as obj_class
from 
	pg_catalog.pg_class c
join pg_catalog.pg_namespace n
	on n.oid = c.relnamespace 
where 
	c.relkind in ('r'::"char", 'p'::"char", 'v'::"char", 'm'::"char")
union all 
select 
	p.oid as obj_id
	, ${mainSchemaName}.f_target_routine_name(
		i_target_routine_id => p.oid
	) as obj_name
	, n.nspname as obj_schema
	, n.nspname || '.' || p.proname as obj_full_name
	, p.prokind as obj_type
	, 'routine'::name as obj_class
from 
	pg_catalog.pg_proc p
join pg_catalog.pg_namespace n
	on n.oid = p.pronamespace
;

comment on view v_sys_obj is 'Объект базы данных';
