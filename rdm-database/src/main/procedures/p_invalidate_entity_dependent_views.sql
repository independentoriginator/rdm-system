create or replace procedure p_invalidate_entity_dependent_views(
	i_type_id ${mainSchemaName}.meta_type.id%type
)
language plpgsql
as $procedure$
begin
	with recursive 
		meta_type as (
			select 
				t.internal_name
				, coalesce(s.internal_name, '${mainSchemaName}') as schema_name
			from 
				${mainSchemaName}.meta_type t
			left join ${mainSchemaName}.meta_schema s 
				on s.id = t.schema_id
			where 
				t.id = i_type_id		
		)
		, v_sys_obj_dependency as (
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
			join meta_type t 
				on t.internal_name = dep.master_obj_name
				and t.schema_name = dep.master_obj_schema
			where
				dep.master_obj_class = 'relation'
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
				v.id
			from 
				${mainSchemaName}.meta_view v
			left join ${mainSchemaName}.meta_schema s
				on s.id = v.schema_id
			join dependent
				on dependent.cls_name = v.internal_name 
				and dependent.cls_schema = coalesce(s.internal_name, '${mainSchemaName}')
			where
				v.is_valid = true
			for update of v
		)
	update 
		${mainSchemaName}.meta_view v
	set 
		is_valid = false
	from 
		dependent_view d
	where 
		v.id = d.id
	;
end
$procedure$;		