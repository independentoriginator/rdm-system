create or replace view v_sys_partitioned_table
as
select 
	n.nspname as schema_name
	, t.relname as table_name
from 
	pg_catalog.pg_class t
join pg_catalog.pg_namespace n
	on n.oid = t.relnamespace
where
	t.relkind = 'p'::"char"
;

comment on view v_sys_partitioned_table is 'Секционированная таблица';

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
			and g.table_name = 'v_sys_partitioned_table'
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
				'grant select on ${mainSchemaName}.v_sys_partitioned_table to %s'
				, l_roles 
			)
		;
	end if;
end
$$
;