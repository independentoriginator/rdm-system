create or replace view v_sys_table_partition
as
select 
	n.nspname as schema_name
	, t.relname as table_name
	, pn.nspname as partition_schema_name
	, p.relname as partition_table_name
	, pg_catalog.pg_get_expr(p.relpartbound, p.oid, true) as partition_expression	
from 
	pg_catalog.pg_class t
join pg_catalog.pg_namespace n
	on n.oid = t.relnamespace
join pg_catalog.pg_inherits i 
	on i.inhparent = t.oid	
join pg_catalog.pg_class p
	on p.oid = i.inhrelid
join pg_catalog.pg_namespace pn
	on pn.oid = p.relnamespace
where
	t.relkind = 'p'::"char"
;

comment on view v_sys_table_partition is 'Секционированная таблица. Секция';

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
			and g.table_name = 'v_sys_table_partition'
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
				'grant select on ${mainSchemaName}.v_sys_table_partition to %s'
				, l_roles 
			)
		;
	end if;
end
$$
;