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
		, dependent_view as (
			select 
			from 
				${mainSchemaName}.meta_view v
			join ${mainSchemaName}.meta_schema s
				on s.id = v.schema_id
			join dependent
				on dependent.cls_name = v.internal_name 
				and dependent.cls_schema = coalesce(s.internal_name, '${mainSchemaName}')
			where
				v.is_valid = true
			for update of v
		)
	update ${mainSchemaName}.meta_view meta_view
	set 
		is_valid = false
	from 
		dependent_view
	where
		meta_view.id = dependent_view.id
	;
	
	return null;
end
$$;			
