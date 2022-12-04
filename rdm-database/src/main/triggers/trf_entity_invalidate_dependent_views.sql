create or replace function trf_entity_invalidate_dependent_views()
returns trigger
language plpgsql
as $$
declare 
	l_view_ids ${type.id}[];
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
	select 
		array_agg(v.id)
	into
		l_view_ids
	from (
		select v.id
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
	) v
	;

	update ${mainSchemaName}.meta_view
	set 
		is_valid = false
	where
		id = any(l_view_ids)
	;
	
	return null;
end
$$;			
