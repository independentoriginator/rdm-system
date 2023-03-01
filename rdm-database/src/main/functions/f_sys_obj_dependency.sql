drop function if exists f_sys_obj_dependency(
	text
	, name
	, bool
	, bool
);

drop function if exists f_sys_obj_dependency(
	text
	, name
	, bool
	, bool
	, bool
);

create or replace function f_sys_obj_dependency(
	i_obj_name text
	, i_schema_name name
	, i_is_routine bool
	, i_treat_the_obj_as_dependent bool -- and as master otherwise
	, i_dependency_level_limit integer = null
	, i_exclude_curr_obj bool = true
)
returns table (
	obj_oid oid
	, obj_name text
	, obj_schema name
	, obj_class name
	, obj_type "char"
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
		obj_oid
		, obj_name
		, obj_schema
		, obj_class
		, obj_type
		, dep_level
	) as (
		select 				
			v.oid as obj_oid
			, v.relname::text as obj_name
			, s.nspname as obj_schema
			, 'relation'::name as obj_class
			, v.relkind as obj_type
			, 0 as dep_level
		from 
			pg_catalog.pg_namespace s
		join pg_catalog.pg_class v
			on v.relnamespace = s.oid
			and v.relname = i_obj_name::name
		where 
			s.nspname = i_schema_name::name
			and i_is_routine = false
		union all
		select 				
			p.oid as obj_oid
			, i_obj_name::text as obj_name
			, s.nspname as obj_schema
			, 'routine'::name as obj_class
			, p.prokind as obj_type
			, 0 as dep_level
		from 
			pg_catalog.pg_namespace s
		join pg_catalog.pg_proc p
			on p.pronamespace = s.oid
			and ${mainSchemaName}.f_target_routine_name(
				i_target_routine_id => p.oid
			) = i_obj_name::text
		where 
			s.nspname = i_schema_name::name
			and i_is_routine = true
		union all
		select
			case i_treat_the_obj_as_dependent 
				when true then dep.master_obj_id
				else dep.dependent_obj_id
			end as obj_oid
			, case i_treat_the_obj_as_dependent 
				when true then dep.master_obj_name
				else dep.dependent_obj_name
			end as obj_name
			, case i_treat_the_obj_as_dependent 
				when true then dep.master_obj_schema
				else dep.dependent_obj_schema
			end as obj_schema
			, case i_treat_the_obj_as_dependent 
				when true then dep.master_obj_class
				else dep.dependent_obj_class
			end as obj_class
			, case i_treat_the_obj_as_dependent 
				when true then dep.master_obj_type
				else dep.dependent_obj_type
			end as obj_type
			, case i_treat_the_obj_as_dependent 
				when true then dependent_obj.dep_level - 1
				else dependent_obj.dep_level + 1
			end as dep_level
		from 
			sys_obj_dependency dep
		join dependent_obj 
			on (
				(i_treat_the_obj_as_dependent = true and dependent_obj.obj_oid = dep.dependent_obj_id)
				or (i_treat_the_obj_as_dependent = false and dependent_obj.obj_oid = dep.master_obj_id)
			)
			and (abs(dependent_obj.dep_level) <= i_dependency_level_limit or i_dependency_level_limit is null)
		where 
			not exists (
				select 
					1
				from
					sys_obj_dependency cyclic_dep
				where 	
					cyclic_dep.dependent_obj_id = dep.master_obj_id 
					and cyclic_dep.master_obj_id = dep.dependent_obj_id
			)
	)
select 
	obj_oid
	, obj_name
	, obj_schema
	, obj_class
	, obj_type
	, min(dep_level) as dep_level
from 
	dependent_obj
where 
	i_treat_the_obj_as_dependent = true
	and (dep_level < 0 or i_exclude_curr_obj = false)
group by 
	obj_oid
	, obj_name
	, obj_schema
	, obj_class
	, obj_type
union all
select 
	obj_oid
	, obj_name
	, obj_schema
	, obj_class
	, obj_type
	, max(dep_level) as dep_level
from 
	dependent_obj
where 
	i_treat_the_obj_as_dependent = false
	and (dep_level > 0 or i_exclude_curr_obj = false)
group by 
	obj_oid
	, obj_name
	, obj_schema
	, obj_class
	, obj_type
$function$;