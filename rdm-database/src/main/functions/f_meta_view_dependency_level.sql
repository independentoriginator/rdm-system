create or replace function f_meta_view_dependency_level(
	i_view_oid oid
)
returns integer
language sql
stable
as $function$
with 
	recursive obj(obj_id,n_level) as (
		select i_view_oid as obj_id, 0::integer as n_level
		union all
		select 
			d.master_obj_id as obj_id, dependent_obj.n_level + 1 as n_level
		from
			${mainSchemaName}.v_sys_obj_dependency d 
		join obj dependent_obj on dependent_obj.obj_id = d.dependent_obj_id 
		where 
			d.master_obj_class = 'routine' 
			or d.master_obj_type in ('v'::"char", 'm'::"char")
	)
select 
	max(n_level)
from 
	obj
$function$;		