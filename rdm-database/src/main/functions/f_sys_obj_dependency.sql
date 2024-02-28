drop function if exists f_sys_obj_dependency(
	text
	, name
	, boolean
	, boolean
);

drop function if exists f_sys_obj_dependency(
	text
	, name
	, boolean
	, boolean
	, boolean
);

drop function if exists f_sys_obj_dependency(
	text
	, name
	, boolean
	, boolean
	, integer
	, boolean
);

drop function if exists f_sys_obj_dependency(
	jsonb
	, boolean
	, integer
	, boolean
);

drop function if exists f_sys_obj_dependency(
	jsonb
	, boolean
	, integer
	, boolean
	, boolean
);

create or replace function f_sys_obj_dependency(
	i_objects jsonb
	, i_treat_the_obj_as_dependent boolean -- and as master otherwise
	, i_dependency_level_limit integer = null
	, i_exclude_the_obj_specified boolean = true
	, i_exclude_system_objects boolean = false
)
returns 
	table (
		obj_id oid
		, dep_obj_id oid
		, dep_obj_name text
		, dep_obj_schema name
		, dep_obj_class name
		, dep_obj_type "char"
		, dep_level integer
	)
language sql
as $function$
with recursive
 	sys_obj_dependency as (
 		select 
 			*
 		from
 			${mainSchemaName}.v_sys_obj_dependency 
 	)
 	, obj_specified as (
		select 
			o.obj_id
			, o.obj_id as dep_obj_id
			, o.obj_name as dep_obj_name
			, o.obj_schema as dep_obj_schema
			, o.obj_class as dep_obj_class
			, o.obj_type as dep_obj_type
			, 0 as dep_level
			, array[o.obj_id] as dep_seq 
		from 
			${mainSchemaName}.v_sys_obj o
		join jsonb_to_recordset(i_objects) as obj(obj_schema name, obj_name text, obj_class name)
			on obj.obj_name = o.obj_name  
			and obj.obj_schema = o.obj_schema
			and obj.obj_class = o.obj_class
 	)
	, master_obj(
		obj_id
		, dep_obj_id
		, dep_obj_name
		, dep_obj_schema
		, dep_obj_class
		, dep_obj_type
		, dep_level
	) as (
		select 
			obj_id
			, dep_obj_id
			, dep_obj_name
			, dep_obj_schema
			, dep_obj_class
			, dep_obj_type
			, dep_level
			, dep_seq 
		from 
			obj_specified
		union all
		select
			master_obj.obj_id
			, dep.master_obj_id as dep_obj_id
			, dep.master_obj_name as dep_obj_name
			, dep.master_obj_schema as dep_obj_schema
			, dep.master_obj_class as dep_obj_class
			, dep.master_obj_type as dep_obj_type
			, master_obj.dep_level - 1 as dep_level
			, master_obj.dep_seq || dep.master_obj_id as dep_seq
		from 
			sys_obj_dependency dep
		join master_obj 
			on master_obj.dep_obj_id = dep.dependent_obj_id
		where 
			dep.master_obj_id <> all(master_obj.dep_seq)
			and (abs(master_obj.dep_level - 1) <= i_dependency_level_limit or i_dependency_level_limit is null)
			and (
				(
					dep.master_obj_schema not like 'pg\_%'
					and dep.master_obj_schema not in ('information_schema', 'public')
				) 
				or not i_exclude_system_objects
			)
	)
	, dependent_obj(
		obj_id
		, dep_obj_id
		, dep_obj_name
		, dep_obj_schema
		, dep_obj_class
		, dep_obj_type
		, dep_level
	) as (
		select 
			obj_id
			, dep_obj_id
			, dep_obj_name
			, dep_obj_schema
			, dep_obj_class
			, dep_obj_type
			, dep_level
			, dep_seq 
		from 
			obj_specified
		union all
		select
			dependent_obj.obj_id
			, dep.dependent_obj_id as dep_obj_id
			, dep.dependent_obj_name as dep_obj_name
			, dep.dependent_obj_schema as dep_obj_schema
			, dep.dependent_obj_class as dep_obj_class
			, dep.dependent_obj_type as dep_obj_type
			, dependent_obj.dep_level + 1 as dep_level
			, dependent_obj.dep_seq || dep.dependent_obj_id as dep_seq
		from 
			sys_obj_dependency dep
		join dependent_obj 
			on dependent_obj.dep_obj_id = dep.master_obj_id
		where 
			dep.dependent_obj_id <> all(dependent_obj.dep_seq)
			and (abs(dependent_obj.dep_level + 1) <= i_dependency_level_limit or i_dependency_level_limit is null)
			and (
				(
					dep.dependent_obj_schema not like 'pg\_%'
					and dep.dependent_obj_schema not in ('information_schema', 'public')
				) 
				or not i_exclude_system_objects
			)
	)
select 
	obj_id
	, dep_obj_id
	, dep_obj_name
	, dep_obj_schema
	, dep_obj_class
	, dep_obj_type
	, min(dep_level) as dep_level
from 
	master_obj
where 
	i_treat_the_obj_as_dependent
	and (dep_level < 0 or i_exclude_the_obj_specified = false)
group by 
	obj_id
	, dep_obj_id
	, dep_obj_name
	, dep_obj_schema
	, dep_obj_class
	, dep_obj_type
union all
select 
	obj_id
	, dep_obj_id
	, dep_obj_name
	, dep_obj_schema
	, dep_obj_class
	, dep_obj_type
	, max(dep_level) as dep_level
from 
	dependent_obj
where 
	not i_treat_the_obj_as_dependent
	and (dep_level > 0 or i_exclude_the_obj_specified = false)
group by 
	obj_id
	, dep_obj_id
	, dep_obj_name
	, dep_obj_schema
	, dep_obj_class
	, dep_obj_type
$function$;

comment on function f_sys_obj_dependency(
	jsonb
	, boolean
	, integer
	, boolean
	, boolean
) is 'Зависимости системного объекта';