create or replace function trf_entity_invalidate_dependent_views()
returns trigger
language plpgsql
as $$
begin
	with recursive 
		v_sys_obj_dependency as (
			select 
				*
			from 
				ng_rdm.v_sys_obj_dependency
		)
		, dependent as (
			select distinct
				dep.dependent_obj_id as cls_oid
				, dep.dependent_obj_name as cls_name
				, dep.dependent_obj_schema as cls_schema
			from 
				v_sys_obj_dependency dep
			where
				dep.master_obj_name = TG_TABLE_NAME
				and dep.master_obj_schema = TG_TABLE_SCHEMA
				and dep.master_obj_class = 'relation'
			union
			select distinct
				dep.dependent_obj_id as cls_oid
				, dep.dependent_obj_name as cls_name
				, dep.dependent_obj_schema as cls_schema
			from 
				dependent
			join v_sys_obj_dependency dep
				on dep.master_obj_id = dependent.cls_oid
		)
	update ${mainSchemaName}.meta_view meta_view
	set 
		is_valid = false
	from 
		dependent
	where
		dependent.cls_name = meta_view.internal_name 
		and dependent.cls_schema = 
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
