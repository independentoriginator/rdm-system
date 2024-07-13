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
	, t.table_id
from (
	select 
		n.nspname as schema_name
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
			t.relnamespace
			, t.oid
			, t.relname
			, t.relkind
			, pg_catalog.pg_relation_size(t.oid) as relation_size
			, pg_catalog.pg_table_size(t.oid) as table_size
			, pg_catalog.pg_indexes_size(t.oid) as indexes_size
			, pg_catalog.pg_total_relation_size(t.oid) as total_relation_size
		from (
			select 
				t.relnamespace
				, t.oid
				, t.relname
				, t.relkind
			from 
				pg_catalog.pg_class t
			where
				t.relkind = any('{r, m}'::"char"[])
			except 
			select 
				p.relnamespace
				, p.oid
				, p.relname
				, p.relkind
			from 
				pg_catalog.pg_class p
			join pg_catalog.pg_inherits i 
				on i.inhrelid = p.oid	
			join pg_catalog.pg_class t
				on t.oid = i.inhparent
				and t.relkind = 'p'::"char"
			where 
				t.relkind = 'r'::"char"
		) t 
		union all
		select 
			t.relnamespace
			, t.oid
			, t.relname
			, t.relkind
			, sum(pg_catalog.pg_relation_size(p.oid))::bigint as relation_size
			, sum(pg_catalog.pg_table_size(p.oid))::bigint as table_size
			, sum(pg_catalog.pg_indexes_size(p.oid))::bigint as indexes_size
			, sum(pg_catalog.pg_total_relation_size(p.oid))::bigint as total_relation_size
		from 
			pg_catalog.pg_class t
		join pg_catalog.pg_inherits i 
			on i.inhparent = t.oid	
		join pg_catalog.pg_class p
			on p.oid = i.inhrelid
		where
			t.relkind = 'p'::"char"
		group by
			t.relnamespace
			, t.oid
			, t.relname
			, t.relkind
	) t
	join pg_catalog.pg_namespace n
		on n.oid = t.relnamespace
) t
;

comment on view v_sys_table_size is 'Размер таблиц';

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