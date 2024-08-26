drop view if exists v_meta_trigger
;

create view v_meta_trigger
as
select
	t.meta_type_id
	, t.meta_view_id
	, t.event_object_schema
	, t.event_object_table
	, format(
		'tr_%s_%s_%s_%s'
		, t.trigger_base_name
		, substr(t.action_timing, 1, 1)
		, t.event_manipulation
		, substr(t.action_orientation, 1, 1)
	) as trigger_name
	, t.action_timing
	, t.event_manipulation
	, t.action_reference_old_table
	, t.action_reference_new_table
	, t.action_orientation
	, format(
		'trf_%s_%s_%s_%s'
		, t.trigger_base_name
		, substr(t.action_timing, 1, 1)
		, t.event_manipulation
		, substr(t.action_orientation, 1, 1)
	) as function_name
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
		dep.master_type_id as meta_type_id
		, dep.master_view_id as meta_view_id
		, coalesce(mv.schema_name, mt.schema_name) as event_object_schema
		, coalesce(mv.internal_name, mt.internal_name) as event_object_table
		, lower(
			${mainSchemaName}.f_abbreviate_name(
				i_name => coalesce(mv.internal_name, mt.internal_name)
				, i_adjust_to_max_length => true
				, i_max_length => 
					${mainSchemaName}.f_system_name_max_length()
					- length('trf__ainsert_s')
			)
		) as trigger_base_name	
		, 'after' as action_timing
		, operation.name as event_manipulation
		, case 
			when operation.name in ('update', 'delete')
			then 'old_table'
		end as action_reference_old_table
		, case 
			when operation.name in ('insert', 'update')
			then 'new_table'
		end as action_reference_new_table
		, 'statement' as action_orientation
		, ${mainSchemaName}.f_indent_text(
			i_text => 
				format(
					E'delete from'
					'\n	%I.%I_chunk chunk'
					'\nusing ('
					'\n	select'
					'\n		chunk.id'
					'\n	from ('
					'\n		%s'
					'\n	) as chunk(id)'
					'\n) invalidated_chunk'
					'\nwhere'
					'\n	invalidated_chunk.id = chunk.%s'
					, v.schema_name
					, v.internal_name
					, ${mainSchemaName}.f_indent_text(
						i_text => 
							replace(
								dep.invalidated_chunk_query_tmpl
								, '{{transition_table}}'
								, transition_table.name
							)
						, i_indentation_level => 2
					)
					, v.mv_emulation_chunking_field
				)
			, i_indentation_level => 1
		) as function_body
		, 'null' as function_return_expr
		, v.mv_emulation_filled_chunk_table_creation_cmd as preparation_command
	from									
		${mainSchemaName}.meta_view_chunk_dependency dep
	join ${mainSchemaName}.v_meta_view v
		on v.id = dep.view_id
	left join ${mainSchemaName}.v_meta_view mv
		on mv.id = dep.master_view_id
	left join ${mainSchemaName}.v_meta_type mt
		on mt.id = dep.master_type_id
	cross join (
			values
				('insert')
				, ('update')
				, ('delete')
		) as operation(name)
	join (
			values
				('old_table')
				, ('new_table')
		) transition_table(name)
		on (
			transition_table.name = 'old_table'
			and operation.name in ('update', 'delete')
		)
		or (
			transition_table.name = 'new_table'
			and operation.name in ('insert', 'update')
		)
) t
group by 
	t.meta_type_id
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
;

comment on view v_meta_trigger is 'Метатриггеры';
