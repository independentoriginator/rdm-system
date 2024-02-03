create or replace view v_meta_view
as
select
	v.id
	, v.internal_name
	, v.dependency_level
	, v.schema_id
	, coalesce(s.internal_name, '${mainSchemaName}') as schema_name
	, (target_schema.obj_id is not null) as is_schema_exists
	, (target_view.obj_id is not null) as is_view_exists
	, case when 'is_materialized' = any(target_view.flags) then true else false end as is_materialized
	, (v.is_created and target_view.obj_id is not null) as is_created
	, v.query
	, v.is_valid
	, v.refresh_time	
	, v.creation_order
	, v.is_disabled
	, v.is_external
	, (
		select 
			max(dep.level)
		from 
			${mainSchemaName}.meta_view_dependency dep
		where
			dep.view_id = v.id
			and dep.master_view_id is not null
	) as previously_defined_dependency_level
	, v.is_routine
	, target_view.obj_id as view_oid
	, coalesce(
		target_view.obj_specific_type::text
		, case 
			when v.is_routine then 'routine'::text
			else 'view'::text
		end
	) as view_type
	, target_view.obj_description as description
	, case 
		when exists (
			select
				1
			from 
				pg_catalog.pg_index ui
			join pg_catalog.pg_class c 
				on c.oid = ui.indrelid
			join pg_catalog.pg_namespace ns
				on ns.oid = c.relnamespace
			where
				ns.nspname = target_view.obj_schema
				and c.relname = target_view.obj_name
				and ui.indisunique
				and ui.indpred is null
		) then true
		else false
	end as has_unique_index	
	, case when 'is_populated' = any(target_view.flags) then true else false end as is_populated
	, v.modification_time
	, v.group_id
from 
	${mainSchemaName}.meta_view v
left join ${mainSchemaName}.meta_schema s
	on s.id = v.schema_id
left join ${mainSchemaName}.v_sys_obj target_schema
	on target_schema.obj_name = coalesce(s.internal_name, '${mainSchemaName}')
	and target_schema.obj_class = 'schema'::name 
left join ${mainSchemaName}.v_sys_obj target_view
	on target_view.obj_schema = target_schema.obj_name
	and target_view.obj_name = v.internal_name
	and target_view.obj_general_type in (
		'view'::name
		, 'routine'::name
	)
;

comment on view v_meta_view is 'Метапредставления';
