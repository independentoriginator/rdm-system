create or replace view v_meta_view
as
select
	v.id
	, v.internal_name
	, v.dependency_level
	, v.schema_id
	, v.schema_name
	, v.is_schema_exists
	, v.is_view_exists
	, v.is_materialized
	, v.is_created
	, v.query
	, (
		v.is_valid 
		and v.is_populated
	) as is_valid  
	, v.refresh_time	
	, v.creation_order
	, v.is_disabled
	, v.is_external
	, v.previously_defined_dependency_level
	, v.is_routine
	, v.view_oid
	, v.view_type
	, v.description
	, (v.unique_index_columns is not null) as has_unique_index	
	, v.is_populated
	, v.modification_time
	, v.group_id
	, v.obj_class
	, v.is_matview_emulation
	, v.mv_emulation_chunking_field
	, v.mv_emulation_chunks_query
	, v.mv_emulation_refresh_proc_name 
	, v.mv_emulation_refresh_proc_param
	, v.mv_emulation_refresh_proc_oid
	, v.mv_emulation_chunks_bucket_size
	, v.mv_emulation_with_partitioning
	, v.mv_emulation_table_func_name
	, v.is_mv_emulation_chunk_validated
	, v.unique_index_columns
	, v.mv_emulation_chunk_row_limit
	, case
		when v.is_mv_emulation_chunk_validated 
			and not v.is_mv_emulation_filled_chunk_table_exists
		then
			-- creation of a service table that will contain a list of filled chunks
			format('
				create table %I.%I
				as 
				select %s, null::timestamp as refresh_time
				from %I.%I 
				where false
				;
				alter table %I.%I
					add primary key(%s)
				'
				, v.schema_name
				, v.mv_emulation_filled_chunk_table_name
				, v.mv_emulation_chunking_field
				, v.schema_name
				, v.internal_name
				, v.schema_name
				, v.mv_emulation_filled_chunk_table_name
				, v.mv_emulation_chunking_field
			)
	end as mv_emulation_filled_chunk_table_creation_cmd
	, case
		when v.is_mv_emulation_chunk_validated 
			and v.is_mv_emulation_filled_chunk_table_exists
		then
			format('
				truncate %I.%I
				'
				, v.schema_name
				, v.mv_emulation_filled_chunk_table_name
			)
	end as mv_emulation_filled_chunk_table_truncation_cmd
from (
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
 		, (
 			select
 				string_agg(
 					a.attname
 					, ', ' 
 					order by 
 						array_position(
 							unique_index.indkey
 							, a.attnum
 						)
 				) as columns 
 			from (
 				select 
 					unique_index.indexrelid
 					, unique_index.indrelid
 					, unique_index.indkey
 				from 
	 				pg_catalog.pg_index unique_index
	 			where 
	 				unique_index.indrelid = target_view.obj_id
	 				and unique_index.indisunique
	 				and unique_index.indpred is null
	 			order by
	 				unique_index.indexrelid
	 			limit 1
	 		) unique_index
 			join pg_catalog.pg_attribute a
 				on a.attrelid = unique_index.indrelid
 				and a.attnum = any(unique_index.indkey)
 		) as unique_index_columns
		, case
			when 
				v.is_matview_emulation 
				and target_view.obj_id is not null
				and v.refresh_time >= v.modification_time
			then true
			when 'is_populated' = any(target_view.flags) 
			then true 
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
		, (
			v.is_matview_emulation
			and v.mv_emulation_chunking_field is not null
			and exists (
				select 
					1
				from 
					${mainSchemaName}.meta_view_chunk_dependency dep
				where 
					dep.view_id = v.id
					and dep.chunking_field = v.mv_emulation_chunking_field
			)
		) as is_mv_emulation_chunk_validated
		, v.internal_name || '_chunk' as mv_emulation_filled_chunk_table_name
		, (target_chunk_table.oid is not null) as is_mv_emulation_filled_chunk_table_exists
		, v.mv_emulation_chunk_row_limit
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
	left join pg_catalog.pg_class target_chunk_table
		on target_chunk_table.relnamespace = target_schema.obj_id 
		and target_chunk_table.relname = v.internal_name || '_chunk'
		and target_chunk_table.relkind = 'r'::"char"
) v
;

comment on view v_meta_view is 'Метапредставления';
