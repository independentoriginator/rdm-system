create or replace view v_sys_table_size
as
select 
	t.schema_name
	, t.table_name
	, t.sys_obj_type
	, t.relation_size as n_relation_size
	, pg_catalog.pg_size_pretty(t.relation_size) as s_relation_size	
	, t.table_size as n_table_size
	, pg_catalog.pg_size_pretty(t.table_size) as s_table_size	
	, t.indexes_size as n_indexes_size
	, pg_catalog.pg_size_pretty(t.indexes_size) as s_indexes_size
	, t.total_relation_size as n_total_relation_size
	, pg_catalog.pg_size_pretty(t.total_relation_size) as s_total_relation_size	
from (
	select 
		n.nspname as schema_name
		, t.relname as table_name
		, case t.relkind
			when 'm'::"char" then 'materialized view'
			else 'table'			
		end as sys_obj_type
		, pg_catalog.pg_relation_size(t.oid) as relation_size
		, pg_catalog.pg_table_size(t.oid) as table_size
		, pg_catalog.pg_indexes_size(t.oid) as indexes_size
		, pg_catalog.pg_total_relation_size(t.oid) as total_relation_size
	from 
		pg_catalog.pg_class t
	join pg_catalog.pg_namespace n
		on n.oid = t.relnamespace
	where
		t.relkind in ('r'::"char", 'p'::"char", 'm'::"char")
) t
;

do $$
declare 
	l_roles text := (
		select 
			string_agg(
				r.rolname
				, ', '
			)			
		from 
			pg_catalog.pg_roles r
		left join information_schema.role_table_grants g
			on g.grantee = r.rolname
			and g.privilege_type = 'SELECT'
			and g.table_name = 'v_sys_table_size'
			and g.table_schema = '${mainSchemaName}'
		where 
			r.rolname in (
				'${mainEndUserRole}'
				, '${etlUserRole}'
			)
	)
	;
begin
	if l_roles is not null then
		execute 
			format(
				'grant select on ${mainSchemaName}.v_sys_table_size to %s'
				, l_roles 
			)
		;
	end if;
end
$$
;