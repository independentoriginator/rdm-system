create or replace view v_sys_table_index
as
select 
	n.nspname as schema_name
	, t.relname as table_name
	, c.relname as index_name
	, i.indisunique as is_unique
	, index_col.index_columns
from 
	pg_catalog.pg_index i
join pg_catalog.pg_class c 
	on c.oid = i.indexrelid
join pg_catalog.pg_class t 
	on t.oid = i.indrelid
join pg_catalog.pg_namespace n
	on n.oid = t.relnamespace
cross join lateral (
	select 
		string_agg(
			a.attname
			, ', ' 
			order by array_position(i.indkey, a.attnum)
		) as index_columns
	from 
		pg_catalog.pg_attribute a
	where
		a.attrelid = i.indrelid
		and a.attnum = any(i.indkey)
) index_col 
;

comment on view v_sys_table_index is 'Индекс';

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
			and g.table_name = 'v_sys_table_index'
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
				'grant select on ${mainSchemaName}.v_sys_table_index to %s'
				, l_roles 
			)
		;
	end if;
end
$$
;