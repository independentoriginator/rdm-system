create or replace view v_sys_partitioned_table
as
select 
	n.nspname as schema_name
	, t.relname as table_name
	, t.oid as table_id
	, t.relnamespace as schema_id
	, case pt.partstrat
		when 'l' then 'list'
		when 'r' then 'range'
		when 'h' then 'hash'
		else pt.partstrat::text
	end as partitioning_strategy
	, partition_key.partition_key_columns as partition_key
from 
	pg_catalog.pg_class t
join pg_catalog.pg_namespace n
	on n.oid = t.relnamespace
join pg_catalog.pg_partitioned_table pt 
	on pt.partrelid = t.oid
join lateral (
	select 
		string_agg(a.attname, ', ' order by pkc.index) as partition_key_columns
	from 
		unnest(pt.partattrs) pkc(index)
	join pg_catalog.pg_attribute a
		on a.attrelid = pt.partrelid
		and a.attnum = pkc.index
) partition_key 
	on true
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