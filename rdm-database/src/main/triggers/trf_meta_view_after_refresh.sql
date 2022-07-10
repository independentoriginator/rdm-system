create or replace function trf_meta_view_after_refresh()
returns trigger
language plpgsql
as $$
begin
	update ${mainSchemaName}.meta_view meta_view
	set 
		is_valid = false
	from 
		${mainSchemaName}.v_sys_obj_dependency dep
	where
		dep.master_obj_name = old.internal_name
		and dep.master_obj_schema = 
			coalesce((
					select 
						s.internal_name
					from 
						${mainSchemaName}.meta_schema s
					where
						s.id = old.schema_id						
				)
				, '${mainSchemaName}'
			)		
		and dep.dependent_obj_name = meta_view.internal_name 
		and dep.dependent_obj_schema = 
			coalesce((
					select 
						s.internal_name
					from 
						${mainSchemaName}.meta_schema s
					where
						s.id = meta_view.schema_id						
				)
				, '${mainSchemaName}'
			)
		and meta_view.is_valid = true
	;

	return null;
end
$$;			
