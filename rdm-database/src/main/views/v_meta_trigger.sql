create or replace view v_meta_trigger
as
with 
	table_object as (
		select 
			t.id as meta_type_id
			, null::${type.id} as meta_view_id
			, t.id as object_id
			, t.schema_name as object_schema
			, t.internal_name as object_table
		from 
			${mainSchemaName}.v_meta_type t
		union all
		select 
			null::${type.id} as meta_type_id
			, t.id as meta_view_id
			, t.id as object_id
			, t.schema_name as object_schema
			, t.internal_name as object_table
		from 
			${mainSchemaName}.v_meta_view t
		where 
			t.is_matview_emulation
	)
	, trigger_operation as (
		select 
			'after'::text as action_timing
			, operation.name as event_manipulation
			, transition_table.name as transition_table 
			, case 
				when operation.name in ('update', 'delete')
				then 'old_table'::name
			end as action_reference_old_table
			, case 
				when operation.name in ('insert', 'update')
				then 'new_table'::name
			end as action_reference_new_table
			, 'statement'::text as action_orientation
		from (
			values
				('insert'::text)
				, ('update'::text)
				, ('delete'::text)
		) as operation(name)
		join (
				values
					('old_table'::name)
					, ('new_table'::name)
			) transition_table(name)
			on (
				transition_table.name = 'old_table'
				and operation.name in ('update', 'delete')
			)
			or (
				transition_table.name = 'new_table'
				and operation.name in ('insert', 'update')
			)
	)
	, log_trigger as (
		select 
			't' || t.id::varchar as trigger_id 
			, t.id as meta_type_id
			, trigger_operation.action_timing
			, trigger_operation.event_manipulation
			, trigger_operation.action_reference_old_table
			, trigger_operation.action_reference_new_table
			, trigger_operation.action_orientation
			, ${mainSchemaName}.f_indent_text(
				i_text => 
					format(
						E'insert into'
						'\n	%I.%I('
						'\n		operation'
						'\n		, %s'
						'\n	)'
						'\nselect distinct'
						'\n	%L::"char"'
						'\n	, %s'
						'\nfrom'
						'\n	%s'
						, t.schema_name
						, t.log_table_name
						, ${mainSchemaName}.f_indent_text(
							i_text => a.logged_attributes
							, i_indentation_level => 2
						)
						, upper(left(trigger_operation.event_manipulation, 1))
						, ${mainSchemaName}.f_indent_text(
							i_text => a.logged_attributes
							, i_indentation_level => 1
						)
						, trigger_operation.transition_table
					)
				, i_indentation_level => 1
			) as function_body
			, 'null'::text as function_return_expr
			, null::text as preparation_command
		from 
			${mainSchemaName}.v_meta_type t 
		join (
			select 
				a.master_id as type_id
				, string_agg(
					a.internal_name 
					|| case 
						when a.is_referenced_type_temporal then
							E'\n, ' || a.version_ref_name
						else ''
					end					
					, E'\n, ' order by a.ordinal_position nulls last
				) as logged_attributes
			from
				${mainSchemaName}.v_meta_attribute a
			where 
				a.is_logged
			group by 
				a.master_id		
		) a 
			on a.type_id = t.id 
		join trigger_operation
			on trigger_operation.action_timing = 'after'
			and (
				trigger_operation.transition_table = 'new_table'
				or trigger_operation.event_manipulation <> 'update' 
			)
		where 
			t.is_logged
	)
	, chunk_invalidation_trigger as (
		select 
			't' || c.type_id::varchar as trigger_id 
			, c.type_id as meta_type_id
			, null::${type.id} as meta_view_id
			, trigger_operation.action_timing
			, trigger_operation.event_manipulation
			, trigger_operation.action_reference_old_table
			, trigger_operation.action_reference_new_table
			, trigger_operation.action_orientation
			, ${mainSchemaName}.f_indent_text(
				i_text => 
					format(
						E'\ninsert into'
						'\n	%I.%I('
						'\n		source_id'
						'\n		, %s'
						'\n	)'
						'\nselect distinct'
						'\n	source_id'				
						'\n	, %s'
						'\nfrom'
						'\n	%s'
						'\nwhere'
						'\n	source_id = any(('
						'\n		select'
						'\n			array_agg(id)'
						'\n		from'
						'\n			${mainSchemaName}.source'
						'\n		where'
						'\n			internal_name in ('
						'\n				%s'
						'\n			)'
						'\n	))'
						'\n;'
						, t.schema_name
						, t.invalidated_chunk_table_name
						, c.chunking_field
						, c.chunking_field
						, trigger_operation.transition_table
						, c.data_source_list
					)
				, i_indentation_level => 1
			) as function_body
			, 'null'::text as function_return_expr
			, null::text as preparation_command
		from (
			select 
				c.type_id
				, c.chunking_field
				, string_agg(
					quote_literal(s.internal_name)
					, ', '
				) as data_source_list
			from 
				${mainSchemaName}.meta_type_invalidated_chunk c
			join ${mainSchemaName}.source s  
				on s.id = c.source_id
			where 
				not c.is_disabled
			group by 
				c.type_id
				, c.chunking_field
		) c	
		join ${mainSchemaName}.v_meta_type t 
			on t.id = c.type_id
		join trigger_operation
			on trigger_operation.action_timing = 'after'
		union all
		select 
			coalesce(
				't' || dep.master_type_id::varchar
				, 'v' || dep.master_view_id::varchar
			) as trigger_id 
			, dep.master_type_id as meta_type_id
			, dep.master_view_id as meta_view_id
			, trigger_operation.action_timing
			, trigger_operation.event_manipulation
			, trigger_operation.action_reference_old_table
			, trigger_operation.action_reference_new_table
			, trigger_operation.action_orientation
			, ${mainSchemaName}.f_indent_text(
				i_text => 
					${mainSchemaName}.f_meta_view_chunk_invalidation_command(
						i_dependent_view_schema => v.schema_name
						, i_dependent_view_name => v.internal_name
						, i_mv_emulation_chunking_field => v.mv_emulation_chunking_field
						, i_invalidated_chunk_query_tmpl => dep.invalidated_chunk_query_tmpl
						, i_transition_table_name => trigger_operation.transition_table
					)
				, i_indentation_level => 1
			) as function_body
			, 'null'::text as function_return_expr
			, null::text as preparation_command
		from									
			${mainSchemaName}.meta_view_chunk_dependency dep
		join ${mainSchemaName}.v_meta_view v
			on v.id = dep.view_id
		join trigger_operation
			on trigger_operation.action_timing = 'after'
	)
select
	t.trigger_id
	, target_trigger.trigger_id as target_trigger_id
	, coalesce(t.meta_type_id, target_trigger.meta_type_id) as meta_type_id
	, coalesce(t.meta_view_id, target_trigger.meta_view_id) as meta_view_id
	, coalesce(t.event_object_schema, target_trigger.schema_name) as event_object_schema
	, coalesce(t.event_object_table, target_trigger.table_name) as event_object_table
	, coalesce(t.trigger_name, target_trigger.trigger_name) as trigger_name
	, coalesce(t.action_timing, target_trigger.action_timing) as action_timing
	, coalesce(t.event_manipulation, target_trigger.event_manipulation) as event_manipulation
	, coalesce(t.action_reference_old_table, target_trigger.action_reference_old_table) as action_reference_old_table
	, coalesce(t.action_reference_new_table, target_trigger.action_reference_new_table) as action_reference_new_table
	, coalesce(t.action_orientation, target_trigger.action_orientation) as action_orientation
	, coalesce(t.function_schema_name, target_trigger.function_schema_name) as function_schema_name
	, coalesce(t.function_name, target_trigger.function_name) as function_name	
	, target_trigger.function_id as target_function_id
	, t.function_body
	, t.function_return_expr
	, t.preparation_command
from (
	select
		t.trigger_id
		, t.meta_type_id
		, t.meta_view_id
		, t.event_object_schema
		, t.event_object_table
		, case 
			when t.trigger_base_name is not null then
				format(
					'tr_%s_%s_%s_%s'
					, t.trigger_base_name
					, substr(t.action_timing, 1, 1)
					, t.event_manipulation
					, substr(t.action_orientation, 1, 1)
				)
		end as trigger_name
		, t.action_timing
		, t.event_manipulation
		, t.action_reference_old_table
		, t.action_reference_new_table
		, t.action_orientation
		, t.event_object_schema as function_schema_name
		, case 
			when t.trigger_base_name is not null then
				format(
					'trf_%s_%s_%s_%s'
					, t.trigger_base_name
					, substr(t.action_timing, 1, 1)
					, t.event_manipulation
					, substr(t.action_orientation, 1, 1)
				)		
		end as function_name
		, string_agg(
			t.function_body
			, E'\n\t;\n\n\t'
		) as function_body
		, t.function_return_expr
		, string_agg(
			t.preparation_command
			, E'\n\t;\n\n\t'
		) as preparation_command
	from (
		select
			t.trigger_id
			, t.meta_type_id
			, t.meta_view_id
			, t.object_schema as event_object_schema
			, t.object_table as event_object_table
			, case 
				when t.trigger_id is not null then
					lower(
						${mainSchemaName}.f_abbreviate_name(
							i_name => t.object_table
							, i_adjust_to_max_length => true
							, i_max_length => 
								${mainSchemaName}.f_system_name_max_length()
								- length('trf__ainsert_s')
						)
					)			
			end as trigger_base_name
			, t.action_timing
			, t.event_manipulation
			, t.action_reference_old_table
			, t.action_reference_new_table
			, t.action_orientation
			, t.function_body
			, t.function_return_expr
			, t.preparation_command
		from (		
			select 
				o.meta_type_id
				, o.meta_view_id
				, o.object_id
				, o.object_schema
				, o.object_table
				, tr.trigger_id
				, tr.action_timing
				, tr.event_manipulation
				, tr.action_reference_old_table
				, tr.action_reference_new_table
				, tr.action_orientation
				, tr.function_body
				, tr.function_return_expr
				, tr.preparation_command
			from 
				table_object o
			join log_trigger tr
				on tr.meta_type_id = o.meta_type_id
			union all
			select 
				o.meta_type_id
				, o.meta_view_id
				, o.object_id
				, o.object_schema
				, o.object_table
				, tr.trigger_id
				, tr.action_timing
				, tr.event_manipulation
				, tr.action_reference_old_table
				, tr.action_reference_new_table
				, tr.action_orientation
				, tr.function_body
				, tr.function_return_expr
				, tr.preparation_command
			from 
				table_object o
			join chunk_invalidation_trigger tr
				on tr.meta_type_id = o.meta_type_id
			union all
			select 
				o.meta_type_id
				, o.meta_view_id
				, o.object_id
				, o.object_schema
				, o.object_table
				, tr.trigger_id
				, tr.action_timing
				, tr.event_manipulation
				, tr.action_reference_old_table
				, tr.action_reference_new_table
				, tr.action_orientation
				, tr.function_body
				, tr.function_return_expr
				, tr.preparation_command
			from 
				table_object o
			join chunk_invalidation_trigger tr
				on tr.meta_view_id = o.meta_view_id
		) t
	) t
	group by 
		trigger_id
		, t.meta_type_id
		, t.meta_view_id
		, t.event_object_schema
		, t.event_object_table
		, t.trigger_base_name
		, t.action_timing
		, t.event_manipulation
		, t.action_reference_old_table
		, t.action_reference_new_table
		, t.action_orientation
		, t.function_return_expr
) t 
full join (
	select 
		tr.oid as trigger_id
		, ns.nspname as schema_name
		, c.relname as table_name
		, tr.tgname as trigger_name
		, em.operation as event_manipulation
		, case tr.tgtype::integer & 1
            when 1 then 'row'::text
            else 'statement'::text
        end as action_orientation
        , case tr.tgtype::integer & 66
            when 2 then 'before'::text
            when 64 then 'instead of'::text
            else 'after'::text
        end as action_timing
        , tr.tgoldtable::name as action_reference_old_table
        , tr.tgnewtable::name as action_reference_new_table
        , tr.tgfoid as function_id
        , fns.nspname as function_schema_name
        , f.proname as function_name        
		, o.meta_type_id
		, o.meta_view_id
	from 
		pg_catalog.pg_trigger tr 
	join pg_catalog.pg_class c 
		on c.oid = tr.tgrelid 
	join pg_catalog.pg_namespace ns 
		on ns.oid = c.relnamespace 
	join ( 
		values 
			(4, 'insert'::text)
			, (8, 'delete'::text)
			, (16, 'update'::text)
	) em(id, operation)	
		on (tr.tgtype::integer & em.id) <> 0
	left join pg_catalog.pg_proc f
		on f.oid = tr.tgfoid
	left join pg_catalog.pg_namespace fns
		on fns.oid = f.pronamespace
	join table_object o 
		on o.object_schema = ns.nspname
		and o.object_table = c.relname
	where 
		not tr.tgisinternal
) target_trigger
	on target_trigger.schema_name = t.event_object_schema
	and target_trigger.table_name = t.event_object_table
	and target_trigger.trigger_name = t.trigger_name 
;

comment on view v_meta_trigger is 'Метатриггеры';
