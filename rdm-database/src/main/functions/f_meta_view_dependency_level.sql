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
	, obj(obj_id, n_level) as (
		select i_view_oid as obj_id, 0::integer as n_level
		union all
		select 
			d.master_obj_id as obj_id, dependent_obj.n_level + 1 as n_level
		from
			sys_obj_dependency d 
		join obj dependent_obj on dependent_obj.obj_id = d.dependent_obj_id 
		where 
			(d.master_obj_class = 'routine' or d.master_obj_type in ('v'::"char", 'm'::"char"))
			and not exists (
				select 
					1
				from
					sys_obj_dependency cyclic_dep
				where 	
					cyclic_dep.dependent_obj_id = d.master_obj_id 
					and cyclic_dep.master_obj_id = d.dependent_obj_id
			)
	)
select 
	max(n_level)
from 
	obj
$function$;		