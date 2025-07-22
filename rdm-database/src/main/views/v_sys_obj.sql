create or replace view v_sys_obj
as
select 
	o.obj_id
	, o.obj_name
	, o.obj_schema
	, o.obj_schema || '.' || o.obj_name as obj_full_name
	, o.obj_class
	, o.obj_type
	, o.obj_general_type
	, o.obj_specific_type
	, o.obj_owner
	, o.obj_description
	, o.flags
	, o.unqualified_name
	, o.obj_schema || '.' || o.unqualified_name as schema_qualified_name
	, o.class_id
from (
	select 
		c.oid as obj_id
		, c.relname::text as obj_name
		, c.relname as unqualified_name
		, n.nspname as obj_schema
		, 'relation'::name as obj_class
		, 'pg_class'::regclass::oid as class_id
		, c.relkind as obj_type
		, case 
			when c.relkind = any(array['v', 'm']::char[]) then 'view'::name
			when c.relkind = any(array['i', 'I']::char[]) then 'index'::name
			when c.relkind = 'S'::char then 'sequence'::name
			else 'table'::name
		end as obj_general_type
		, case c.relkind
			when 'v'::"char" then 'view'::name
			when 'm'::"char" then 'materialized view'::name
			when 'f'::"char" then 'foreign table'::name
			when 'i'::"char" then 'index'::name
			when 'I'::"char" then 'index'::name
			when 'S'::char then 'sequence'::name
			else 'table'::name
		end as obj_specific_type
		, obj_owner.rolname as obj_owner
		, d.description as obj_description
		, (
			array[]::text[] 
			|| case 
				when c.relkind = 'm'::"char" then
					array['is_materialized'::text]
			end
			|| case 
				when c.relkind = 'm'::"char" and c.relispopulated then 
					array['is_populated'::text]
			end
			|| case 
				when c.relispartition then
					array['is_partition'::text]
			end
		) as flags
	from 
		pg_catalog.pg_class c
	join pg_catalog.pg_namespace n
		on n.oid = c.relnamespace 
	join pg_catalog.pg_roles obj_owner 
		on obj_owner.oid = c.relowner
	left join pg_catalog.pg_description d 
		on d.objoid = c.oid
		and d.classoid = 'pg_class'::regclass
		and d.objsubid = 0
	where 
		c.relkind = any(array['r', 'p', 'v', 'm', 'f', 'i', 'I', 'S']::char[])
	union all 
	select 
		p.oid as obj_id
		, ${mainSchemaName}.f_target_routine_name(
			i_target_routine_id => p.oid
		) as obj_name
		, p.proname as unqualified_name 
		, n.nspname as obj_schema
		, 'routine'::name as obj_class
		, 'pg_proc'::regclass::oid as class_id
		, p.prokind as obj_type
		, 'routine'::name as obj_general_type
		, case p.prokind
			when 'p'::"char" then 'procedure'::name
			when 'f'::"char" then 'function'::name
			when 'a'::"char" then 'aggregate function'::name
			when 'w'::"char" then 'window function'::name
			else 'routine'::name
		end as obj_specific_type
		, obj_owner.rolname as obj_owner
		, d.description as obj_description
		, array[]::text[] as flags
	from 
		pg_catalog.pg_proc p
	join pg_catalog.pg_namespace n
		on n.oid = p.pronamespace
	join pg_catalog.pg_roles obj_owner 
		on obj_owner.oid = p.proowner
	left join pg_catalog.pg_description d 
		on d.objoid = p.oid
		and d.classoid = 'pg_proc'::regclass
	union all
	select 
		n.oid as obj_id
		, n.nspname as obj_name
		, n.nspname as unqualified_name 
		, n.nspname as obj_schema
		, 'schema'::name as obj_class
		, 'pg_namespace'::regclass::oid as class_id
		, 'n'::"char" as obj_type
		, 'schema'::name as obj_general_type
		, 'schema'::name as obj_specific_type
		, obj_owner.rolname as obj_owner
		, d.description as obj_description
		, array[]::text[] as flags
	from 
		pg_catalog.pg_namespace n
	join pg_catalog.pg_roles obj_owner 
		on obj_owner.oid = n.nspowner
	left join pg_catalog.pg_description d 
		on d.objoid = n.oid
) o
;

comment on view v_sys_obj is 'Объект базы данных';

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
			and g.table_name = 'v_sys_obj'
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
				'grant select on ${mainSchemaName}.v_sys_obj to %s'
				, l_roles 
			)
		;
	end if;
end
$$
;
