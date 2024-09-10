create or replace function f_meta_view_chunk_invalidation_command(
	i_dependent_view_schema ${mainSchemaName}.meta_schema.internal_name%type
	, i_dependent_view_name ${mainSchemaName}.meta_view.internal_name%type
	, i_mv_emulation_chunking_field ${mainSchemaName}.meta_view.mv_emulation_chunking_field%type
	, i_invalidated_chunk_query_tmpl ${mainSchemaName}.meta_view_chunk_dependency.invalidated_chunk_query_tmpl%type
	, i_transition_table_name name
)
returns text
language sql
immutable
parallel safe
as $function$
select
	format(
		E'with'
		'\n	invalidated_chunk as ('
		'\n		select'
		'\n			chunk.id'
		'\n		from ('
		'\n			%s'
		'\n		) as chunk(id)'
		'\n		join %I.%I_chunk c'
		'\n			on c.%s = chunk.id'
		'\n		order by'
		'\n			chunk.id'
		'\n		for update of c'
		'\n	)'
		'\ndelete from'
		'\n	%I.%I_chunk chunk'
		'\nusing'
		'\n	invalidated_chunk'
		'\nwhere'
		'\n	chunk.%s = invalidated_chunk.id'
		, ${mainSchemaName}.f_indent_text(
			i_text => 
				replace(
					i_invalidated_chunk_query_tmpl
					, '{{transition_table}}'
					, i_transition_table_name
				)
			, i_indentation_level => 3
		)
		, i_dependent_view_schema
		, i_dependent_view_name
		, i_mv_emulation_chunking_field
		, i_dependent_view_schema
		, i_dependent_view_name
		, i_mv_emulation_chunking_field
	)
$function$
;	