create or replace function trf_entity_invalidate_dependent_views()
returns trigger
language plpgsql
as $$
begin
	with recursive dependent as (
		select distinct
			dep.dependent_cls_oid as cls_oid
			, dep.dependent_cls_name as cls_name
			, dep.dependent_cls_schema as cls_schema
		from 
			ng_rdm.v_sys_obj_dependency dep
		where
			dep.master_cls_name = TG_TABLE_NAME
			and dep.master_cls_schema = TG_TABLE_SCHEMA
		union
		select distinct
			dep.dependent_cls_oid as cls_oid
			, dep.dependent_cls_name as cls_name
			, dep.dependent_cls_schema as cls_schema
		from 
			dependent
		join ng_rdm.v_sys_obj_dependency dep
			on dep.master_cls_oid = dependent.cls_oid
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
