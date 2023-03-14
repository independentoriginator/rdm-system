create or replace function f_meta_view_dependency_level(
	i_view_oid oid
)
returns integer
language sql
stable
as $function$
with recursive
 	sys_obj_dependency as (
 		select 
 			*
 		from
 			${mainSchemaName}.v_sys_obj_dependency 
 	)
	, obj as (
		select 
			i_view_oid as obj_id
			, 0::integer as n_level
			, array[i_view_oid] as dep_seq 
		union all
		select 
			d.master_obj_id as obj_id
			, dependent_obj.n_level + 1 as n_level
			, dependent_obj.dep_seq || d.master_obj_id as dep_seq 
		from
			sys_obj_dependency d 
		join obj dependent_obj on dependent_obj.obj_id = d.dependent_obj_id 
		where 
			(d.master_obj_class = 'routine' or d.master_obj_type in ('v'::"char", 'm'::"char"))
			and d.master_obj_id <> all(dependent_obj.dep_seq)
	)
select 
	max(n_level)
from 
	obj
$function$;		