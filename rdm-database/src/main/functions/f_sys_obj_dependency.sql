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
		union all
		select 
			d.obj_id
			, d.dep_obj_id
			, d.dep_obj_name
			, d.dep_obj_schema
			, d.dep_obj_class
			, d.dep_obj_type
			, d.dep_level
			, d.dep_seq || d.dep_obj_id as dep_seq
		from (
			select
				dependent_obj.obj_id
				, dep_obj.obj_id as dep_obj_id
				, dep_obj.obj_name as dep_obj_name
				, dep_obj.obj_schema as dep_obj_schema
				, dep_obj.obj_class as dep_obj_class
				, dep_obj.obj_type as dep_obj_type
				, dep_obj.dep_level
				, dependent_obj.dep_seq
			from 
				sys_obj_dependency dep
			join dependent_obj 
				on (
					(i_treat_the_obj_as_dependent = true and dependent_obj.dep_obj_id = dep.dependent_obj_id)
					or (i_treat_the_obj_as_dependent = false and dependent_obj.dep_obj_id = dep.master_obj_id)
				)
				and (abs(dependent_obj.dep_level) <= i_dependency_level_limit or i_dependency_level_limit is null)
			join lateral (
				values
					(
						true
						, dep.master_obj_id
						, dep.master_obj_name
						, dep.master_obj_schema
						, dep.master_obj_class
						, dep.master_obj_type
						, dependent_obj.dep_level - 1
					)
					, (
						false
						, dep.dependent_obj_id
						, dep.dependent_obj_name
						, dep.dependent_obj_schema
						, dep.dependent_obj_class
						, dep.dependent_obj_type
						, dependent_obj.dep_level + 1
					)
			) as dep_obj(
				is_dependent
				, obj_id
				, obj_name
				, obj_schema
				, obj_class
				, obj_type
				, dep_level
			)
				on dep_obj.is_dependent = i_treat_the_obj_as_dependent			
		) d
		where 
			d.dep_obj_id <> all(d.dep_seq)
			and (
				(
					d.dep_obj_schema not like 'pg\_%'
					and d.dep_obj_schema not in ('information_schema', 'public')
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
	dependent_obj
where 
	i_treat_the_obj_as_dependent = true
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
	i_treat_the_obj_as_dependent = false
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