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
	join ${mainSchemaName}.meta_schema s
		on coalesce(s.internal_name, '${mainSchemaName}') = dep.dependent_cls_schema
	where
		dep.master_cls_name = TG_TABLE_NAME
		and dep.master_cls_schema = TG_TABLE_SCHEMA
		and dep.dependent_cls_name = meta_view.internal_name 
		and s.id = meta_view.schema_id
		and meta_view.is_valid = true
	;
	
	return null;
end
$$;			
