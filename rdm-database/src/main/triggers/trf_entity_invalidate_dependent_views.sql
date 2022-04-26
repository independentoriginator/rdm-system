create or replace function trf_entity_invalidate_dependent_views()
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
		dep.master_cls_name = TG_TABLE_NAME
		and dep.master_cls_schema = TG_TABLE_SCHEMA
		and dep.dependent_cls_name = meta_view.internal_name 
		and dep.dependent_cls_schema = 
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
