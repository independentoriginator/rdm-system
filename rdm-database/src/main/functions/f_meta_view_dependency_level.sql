create or replace function f_meta_view_dependency_level(
	i_view_oid oid
)
returns integer
language sql
stable
as $function$
select 
	coalesce((
			select 
				max(${mainSchemaName}.f_meta_view_dependency_level(i_view_oid => t.master_obj_id))
			from
				${mainSchemaName}.v_sys_obj_dependency t 
			where 
				t.dependent_obj_id = i_view_oid
		) + 1,
		0
	)
$function$;		