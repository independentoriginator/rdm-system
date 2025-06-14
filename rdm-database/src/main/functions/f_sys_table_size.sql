create or replace function 
	f_sys_table_size(
		i_schema_name name[] = null
	)
returns 
	table (
		schema_name name
		, table_name name 
		, sys_obj_type text
		, n_relation_size bigint
		, s_relation_size text	
		, n_table_size bigint
		, s_table_size text
		, n_indexes_size bigint
		, s_indexes_size text
		, n_total_relation_size bigint
		, s_total_relation_size text
		, table_id ${type.system_object_id}
	)
language sql
as $function$
with 
	table_schema as (
		select 
			n.oid as id
			, n.nspname as name
		from 
			pg_catalog.pg_namespace n
		where 
			n.nspname = any(i_schema_name)
			or i_schema_name is null 
	)
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
	, t.table_id
from (
	select 
		t.schema_name
		, t.relname as table_name
		, case t.relkind
			when 'm'::"char" then 'materialized view'
			else 'table'			
		end as sys_obj_type
		, t.relation_size
		, t.table_size
		, t.indexes_size
		, t.total_relation_size
		, t.oid as table_id
	from (
		select 
			t.schema_name
			, t.oid
			, t.relname
			, t.relkind
			, pg_catalog.pg_relation_size(t.oid) as relation_size
			, pg_catalog.pg_table_size(t.oid) as table_size
			, pg_catalog.pg_indexes_size(t.oid) as indexes_size
			, pg_catalog.pg_total_relation_size(t.oid) as total_relation_size
		from (
			select 
				s.name as schema_name
				, t.oid
				, t.relname
				, t.relkind
			from 
				pg_catalog.pg_class t
			join table_schema s 
				on s.id = t.relnamespace
			where
				t.relkind = any('{r, m}'::"char"[])
			except 
			select 
				s.name as schema_name
				, p.oid
				, p.relname
				, p.relkind
			from 
				pg_catalog.pg_class p
			join table_schema s 
				on s.id = p.relnamespace
			join pg_catalog.pg_inherits i 
				on i.inhrelid = p.oid	
			join pg_catalog.pg_class t
				on t.oid = i.inhparent
				and t.relkind = 'p'::"char"
			where 
				p.relkind = 'r'::"char"
		) t 
		union all
		select 
			s.name as schema_name
			, t.oid
			, t.relname
			, t.relkind
			, sum(pg_catalog.pg_relation_size(p.oid))::bigint as relation_size
			, sum(pg_catalog.pg_table_size(p.oid))::bigint as table_size
			, sum(pg_catalog.pg_indexes_size(p.oid))::bigint as indexes_size
			, sum(pg_catalog.pg_total_relation_size(p.oid))::bigint as total_relation_size
		from 
			pg_catalog.pg_class t
		join table_schema s 
			on s.id = t.relnamespace
		join pg_catalog.pg_inherits i 
			on i.inhparent = t.oid	
		join pg_catalog.pg_class p
			on p.oid = i.inhrelid
		where
			t.relkind = 'p'::"char"
		group by
			s.name
			, t.oid
			, t.relname
			, t.relkind
	) t
) t
$function$
;

comment on function 
	f_sys_table_size(
		name[]
	) 
	is 'Размер таблиц'
;