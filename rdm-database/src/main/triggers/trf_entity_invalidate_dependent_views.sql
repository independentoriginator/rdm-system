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
	join ${mainSchemaName}.meta_view v
		on v.internal_name = dep.dependent_cls_name 
	join ${mainSchemaName}.meta_schema s
		on s.id = v.schema_id
		and dep.dependent_cls_schema = coalesce(s.internal_name, '${mainSchemaName}')
	where
		dep.master_cls_name = TG_TABLE_NAME
		and dep.master_cls_schema = TG_TABLE_SCHEMA
		and meta_view.is_valid = true
	;
	
	return null;
end
$$;			
