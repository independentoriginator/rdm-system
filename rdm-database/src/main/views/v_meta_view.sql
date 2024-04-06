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
	, case 
		when 'is_materialized' = any(target_view.flags)
			or v.is_matview_emulation
		then true 
		else false 
	end as is_materialized
	, (
		v.is_created 
		and target_view.obj_id is not null
		and (		
			(v.is_routine and target_view.obj_general_type = 'routine'::name)
			or not v.is_routine and (
				(v.is_matview_emulation and target_view.obj_general_type = 'table'::name)
				or (not v.is_matview_emulation and target_view.obj_general_type = 'view'::name)
			)
		)
	) as is_created
	, v.query
	, (
		v.is_valid 
		and case
			when v.is_matview_emulation then (target_view.obj_id is not null)
			when 'is_populated' = any(target_view.flags) then true 
			else false 
		end		
	) as is_valid  
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
	, case
		when v.is_matview_emulation then (target_view.obj_id is not null)
		when 'is_populated' = any(target_view.flags) then true 
		else false 
	end as is_populated
	, v.modification_time
	, v.group_id
	, coalesce(
		target_view.obj_class
		, case 
			when v.is_routine then 'routine'::name
			else 'relation'::name
		end
	) as obj_class
	, v.is_matview_emulation
	, v.mv_emulation_chunking_field
	, v.mv_emulation_chunks_query
	, 'p_refresh_' || v.internal_name as mv_emulation_refresh_proc_name 
	, 'i_' || v.mv_emulation_chunking_field as mv_emulation_refresh_proc_param
	, mve_target_proc.oid as mv_emulation_refresh_proc_oid
	, coalesce(v.mv_emulation_chunks_bucket_size, 1) as mv_emulation_chunks_bucket_size
	, v.mv_emulation_with_partitioning
	, 'f_' || v.internal_name as mv_emulation_table_func_name
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
	and (
		(v.is_routine and target_view.obj_general_type = 'routine'::name)
		or (not v.is_routine and target_view.obj_general_type in ('view'::name, 'table'::name))
	)
left join pg_catalog.pg_proc mve_target_proc
	on mve_target_proc.pronamespace = target_schema.obj_id
	and mve_target_proc.proname = 'p_refresh_' || v.internal_name
	and (
		(mve_target_proc.pronargs = 0 and v.mv_emulation_chunking_field is null)
		or (
			mve_target_proc.pronargs = 1 
			and v.mv_emulation_chunking_field is not null
			and mve_target_proc.proargnames = array['i_' || v.mv_emulation_chunking_field]::text[]
		)
	)
;

comment on view v_meta_view is 'Метапредставления';
