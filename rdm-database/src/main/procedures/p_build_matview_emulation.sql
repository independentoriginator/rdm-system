create or replace procedure p_build_matview_emulation(
	i_view_rec ${mainSchemaName}.v_meta_view
)
language plpgsql
as $procedure$
declare 
	l_sttmnt record;
	l_is_matview_recognized boolean := false;
	l_chunk_invalidation_script text; 
	l_chunk_invalidation_script_subst text;
begin
	select 
		nullif(
			string_agg(
				${mainSchemaName}.f_meta_view_chunk_invalidation_command(
					i_dependent_view_schema => dependent_view.schema_name
					, i_dependent_view_name => dependent_view.internal_name
					, i_mv_emulation_chunking_field => dependent_view.mv_emulation_chunking_field
					, i_invalidated_chunk_query_tmpl => dep.invalidated_chunk_query_tmpl
					, i_transition_table_name => i_view_rec.schema_name || '.%I'
				)
				, E'\n;\n'
			)
			, ''
		)
		, string_agg(
			E'\n	 		, chunk.new_partition'
			, ''
		) 
	into 
		l_chunk_invalidation_script
		, l_chunk_invalidation_script_subst
	from			
		${mainSchemaName}.meta_view_chunk_dependency dep
	join ${mainSchemaName}.v_meta_view dependent_view
		on dependent_view.id = dep.view_id
	where
		dep.master_view_id = i_view_rec.id
	;

	for l_sttmnt in (
		select 
			case 
				when t.view_query is not null then
					concat_ws(
						E';\n'
						-- creation of a table that will replace the materialized view  
						, case 
							when i_view_rec.mv_emulation_with_partitioning 
								and i_view_rec.mv_emulation_chunking_field is not null
							then
								format('
									call 
										${mainSchemaName}.p_recreate_table_as(
											i_table_schema => %L
											, i_table_name => %L
											, i_query => %L
											, i_partitioning_strategy => ''list''
											, i_partition_key => %L
										)			
									'
									, i_view_rec.schema_name
									, i_view_rec.internal_name
									, t.view_query
									, i_view_rec.mv_emulation_chunking_field
								)
							else 
								format('
									call 
										${mainSchemaName}.p_recreate_table_as(
											i_table_schema => %L
											, i_table_name => %L
											, i_query => %L
										)			
									'
									, i_view_rec.schema_name
									, i_view_rec.internal_name
									, t.view_query
								)
						end
						-- creation of a service table that will contain a list of filled chunks
						, i_view_rec.mv_emulation_filled_chunk_table_creation_cmd
						, i_view_rec.mv_emulation_filled_chunk_table_truncation_cmd
						-- generation of a refresh procedure for the emulated materialized view 
						, case 
							when i_view_rec.mv_emulation_chunking_field is null then
								format(
									E'create or replace procedure %I.%I()'
									'\nlanguage plpgsql'
									'\nsecurity definer'
									'\nas $routine$%s'
									'\nbegin'
									'\n\t%s'
									'\nend'
									'\n$routine$;'
									, i_view_rec.schema_name
									, i_view_rec.mv_emulation_refresh_proc_name
									, case 
										when i_view_rec.mv_emulation_chunk_row_limit is not null then 
											format(
												E'\ndeclare'
												'\n	l_row_limit bigint := %s;'
												'\n	l_row_offset bigint := 0;'
												, i_view_rec.mv_emulation_chunk_row_limit
											)
										else 
											''
									end
									, ${mainSchemaName}.f_indent_text(
										i_text => 									
											format(
												E'perform pg_catalog.pg_advisory_xact_lock(''%I.%I''::regclass::bigint)'
												'\n;'
												'\ndelete from'
												'\n	%I.%I'
												'\n;'
												'\n%s'
												, i_view_rec.schema_name
												, i_view_rec.internal_name
												, i_view_rec.schema_name
												, i_view_rec.internal_name
												, case 
													when i_view_rec.mv_emulation_chunk_row_limit is not null then
														format(
															E'<<insertion_in_parts>>'
															'\nloop' 
															'\n	insert into'
															'\n		%I.%I'
															'\n	%s'
															'\n	;'
															'\n	exit insertion_in_parts when not found'
															'\n	;'
															'\n	l_row_offset := l_row_offset + l_row_limit'
															'\n	;'
															'\nend loop insertion_in_parts'
															'\n;'
															, i_view_rec.schema_name
															, i_view_rec.internal_name
															, ${mainSchemaName}.f_indent_text(
																i_text => t.view_query
																, i_indentation_level => 1
															)																
														)
													else
														format(
															E'insert into %I.%I\n%s\n;'
															, i_view_rec.schema_name
															, i_view_rec.internal_name
															, t.view_query
														)
												end
											)
										, i_indentation_level => 1		
									)
								)
							else
								concat_ws(
									E'\n'
									, format(
										E'drop view if exists tv_%I_%I'
										'\n;'										
										'\ncreate temp view tv_%I_%I as'
										'\nselect' 
										'\n	array('
										'\n		select %s from %I.%I limit 0'
										'\n	) as arr_%s'
										'\n;'
										, i_view_rec.internal_name
										, i_view_rec.schema_name
										, i_view_rec.internal_name
										, i_view_rec.schema_name
										, i_view_rec.mv_emulation_chunking_field
										, i_view_rec.schema_name
										, i_view_rec.internal_name
										, i_view_rec.mv_emulation_chunking_field
									)
									, format(
										E'create or replace function %I.%I('
										'\n	%s tv_%I_%I.arr_%s%%type%s'
										'\n)'
										'\nreturns setof %I.%I'
										'\nlanguage plpgsql'
										'\nstable'
										'\nparallel safe'									
										'\nas $routine$'
										'\nbegin'
										'\n	return query'
										'\n		%s'
										'\n	;'
										'\nend'
										'\n$routine$'
										'\n;'
										, i_view_rec.schema_name
										, i_view_rec.mv_emulation_table_func_name
										, i_view_rec.mv_emulation_refresh_proc_param
										, i_view_rec.internal_name
										, i_view_rec.schema_name
										, i_view_rec.mv_emulation_chunking_field
										, case 
											when i_view_rec.mv_emulation_chunk_row_limit is not null then 
												format(
													E'\n	, i_row_limit bigint = %s'
													'\n	, i_row_offset bigint = 0'
													, i_view_rec.mv_emulation_chunk_row_limit
												)
											else 
												''
										end
										, i_view_rec.schema_name
										, i_view_rec.internal_name
										, ${mainSchemaName}.f_indent_text(
											i_text => target_query
											, i_indentation_level => 1		
										)
 									)
									, format(
										E'create or replace procedure %I.%I('
										'\n\t%s tv_%I_%I.arr_%s%%type = null'
										'\n)'
										'\nlanguage plpgsql'
										'\nsecurity definer'
										'\nas $routine$%s'
										'\nbegin'
										'\n	if %s is null then'
										'\n		call'
										'\n			${stagingSchemaName}.p_execute_in_parallel('
										'\n				i_command_list_query => $sql$'
										'\n					select'
										'\n						format('
										'\n							''call %I.%I(%s => %%L)'''
										'\n							, c.%s'
										'\n						) as command'
										'\n						, c.%s::varchar as extra_info'
										'\n					from ('
										'\n						select' 
										'\n							array_agg('
										'\n								c.%s order by c.%s'
										'\n							) as %s'
										'\n						from ('
										'\n							select' 
										'\n								c.%s'
										'\n								, ((row_number() over(order by c.%s) - 1) / %s) + 1 as bucket_num' 
										'\n							from ('
										'\n								%s%s'
										'\n							) c'
										'\n						) c'
										'\n						group by' 
										'\n							c.bucket_num'
										'\n						order by' 
										'\n							c.bucket_num'
										'\n					) c'
										'\n					$sql$'
										'\n				, i_context_id => ''%I.%I''::regproc::integer'
										'\n			)'
										'\n		;%s'
										'\n	else'
										'\n		%s'
										'\n	end if'
										'\n	;'
										'\nend'
										'\n$routine$'
										'\n;'
										, i_view_rec.schema_name
										, i_view_rec.mv_emulation_refresh_proc_name
										, i_view_rec.mv_emulation_refresh_proc_param
										, i_view_rec.internal_name
										, i_view_rec.schema_name
										, i_view_rec.mv_emulation_chunking_field
										, case 
											when i_view_rec.mv_emulation_with_partitioning
												or i_view_rec.mv_emulation_chunk_row_limit is not null
											then
												E'\ndeclare'
												|| case 
													when i_view_rec.mv_emulation_with_partitioning then
														format(
															E'\n	l_chunk_rec record;'
															'\n	l_partition record;'
															'\n	l_meta_view_id ${mainSchemaName}.meta_view.id%%type :='
															'\n		${stagingSchemaName}.f_meta_view_id('
															'\n			i_internal_name => ''%I'''
															'\n			, i_schema_name => ''%I'''											
															'\n		)'											
															'\n	;'
															, i_view_rec.internal_name
															, i_view_rec.schema_name
														)
													else 
														''
												end
												|| case 
													when i_view_rec.mv_emulation_chunk_row_limit is not null then
														format(
															E'\n	l_row_limit bigint := %s;'
															'\n	l_row_offset bigint := 0;'
															, i_view_rec.mv_emulation_chunk_row_limit
														)
													else 
														''
												end
											else 
												''
										end					
										, i_view_rec.mv_emulation_refresh_proc_param
										, i_view_rec.schema_name
										, i_view_rec.mv_emulation_refresh_proc_name
										, i_view_rec.mv_emulation_refresh_proc_param
										, i_view_rec.mv_emulation_chunking_field
										, i_view_rec.mv_emulation_chunking_field
										, i_view_rec.mv_emulation_chunking_field
										, i_view_rec.mv_emulation_chunking_field
										, i_view_rec.mv_emulation_chunking_field
										, i_view_rec.mv_emulation_chunking_field
										, i_view_rec.mv_emulation_chunking_field
										, i_view_rec.mv_emulation_chunks_bucket_size
										, trim(
											${mainSchemaName}.f_indent_text(
												i_text => i_view_rec.mv_emulation_chunks_query									
												, i_indentation_level => 7
											)
										)
										, case 
											when i_view_rec.is_mv_emulation_chunk_validated then
												trim(
													${mainSchemaName}.f_indent_text(
														i_text => 
															format(
																E'\nexcept'
																'\nselect'
																'\n	%s'
																'\nfrom'
																'\n	%I.%I_chunk'
																, i_view_rec.mv_emulation_chunking_field
																, i_view_rec.schema_name
																, i_view_rec.internal_name
															)
														, i_indentation_level => 8
													)
												)
											else ''
										end
										, i_view_rec.schema_name
										, i_view_rec.mv_emulation_refresh_proc_name
										, case 
											when i_view_rec.mv_emulation_with_partitioning then
												${mainSchemaName}.f_indent_text(
													i_text =>
														format(
															E'\n\n-- partitioned table composing/recomposing'
															'\nlock table'
															'\n	%I.%I'
															'\nin access exclusive mode'
															'\n;'
															'\nselect'
															'\n	string_agg('
															'\n		format($ddl$'
															'\n			alter table'
															'\n				%I.%I'
															'\n			detach partition'
															'\n				%I.%%I'
															'\n			$ddl$'
															'\n			, old_partition.partition_table_name'
															'\n		)'
															'\n		, E'';\\n'''
															'\n	) filter ('
															'\n		where '
															'\n			old_partition.partition_table_name is not null'
															'\n	) as old_partitions_detaching'
															'\n	, string_agg('
															'\n		format($ddl$'
															'\n			truncate'
															'\n				%I.%%I'
															'\n			$ddl$'
															'\n			, shadow_table.obj_name'
															'\n		)'
															'\n		, E'';\\n'''
															'\n	) filter ('
															'\n		where '
															'\n			shadow_table.obj_name is not null'
															'\n	) as shadow_tables_truncating'
															'\n	, string_agg('
															'\n		format($ddl$'
															'\n			alter table'
															'\n				%I.%I'
															'\n			attach partition'
															'\n				%I.%%I'
															'\n			for values'
															'\n				%%s'
															'\n			$ddl$'
															'\n			, current_table.obj_name'
															'\n			, p.partition_bound_spec'
															'\n		)'
															'\n		, E'';\\n'''
															'\n	) filter ('
															'\n		where' 
															'\n			current_partition.partition_table_id is null'
															'\n	) as new_partitions_attaching'
															'\ninto'
															'\n	l_partition'
															'\nfrom'
															'\n	${stagingSchemaName}.materialized_view_partition p'
															'\njoin ${mainSchemaName}.v_sys_obj current_table'
															'\n	on current_table.obj_id = p.current_table_id'
															'\nleft join ng_rdm.v_sys_table_partition current_partition'
															'\n	on current_partition.partition_schema_name = current_table.obj_schema'
															'\n	and current_partition.partition_table_name = current_table.obj_name'
															'\n	and current_partition.partition_table_id = current_table.obj_id'
															'\nleft join ${mainSchemaName}.v_sys_obj shadow_table'
															'\n	on shadow_table.obj_id = p.shadow_table_id'
															'\nleft join ${mainSchemaName}.v_sys_table_partition old_partition'
															'\n	on old_partition.schema_name = %L'
															'\n	and old_partition.table_name = %L'
															'\n	and old_partition.partition_table_id = p.shadow_table_id'
															'\nwhere'
															'\n	p.meta_view_id = l_meta_view_id'
															'\n;'
															'\nif l_partition.old_partitions_detaching is not null then'
															'\n	execute'
															'\n		l_partition.old_partitions_detaching'
															'\n	;'
															'\nend if'
															'\n;'
															'\nif l_partition.new_partitions_attaching is not null then'
															'\n	execute'
															'\n		l_partition.new_partitions_attaching'
															'\n	;'
															'\nend if'
															'\n;'
															'\nif l_partition.shadow_tables_truncating is not null then'
															'\n	execute'
															'\n		l_partition.shadow_tables_truncating'
															'\n	;'
															'\nend if'
															'\n;'
															, i_view_rec.schema_name
															, i_view_rec.internal_name
															, i_view_rec.schema_name
															, i_view_rec.internal_name
															, i_view_rec.schema_name
															, i_view_rec.schema_name
															, i_view_rec.schema_name
															, i_view_rec.internal_name
															, i_view_rec.schema_name
															, i_view_rec.schema_name
															, i_view_rec.internal_name
														)
													, i_indentation_level => 2
												)
											else ''
										end
										, ${mainSchemaName}.f_indent_text(
											i_text =>
												format(
													E'perform '
													'\n	pg_catalog.pg_advisory_xact_lock('
													'\n		''%I.%I''::regclass::integer'
													'\n		, hashtext(c::text)'
													'\n	)'
													'\nfrom '
													'\n	unnest(%s) c'
													'\n;'
													, i_view_rec.schema_name
													, i_view_rec.internal_name
													, i_view_rec.mv_emulation_refresh_proc_param
												)
												|| case 
													when i_view_rec.mv_emulation_with_partitioning then
														format(
															E'\n\nselect'
															'\n	string_agg('
															'\n		format($ddl$'
															'\n			create table'
															'\n				%I.%%I('
															'\n					like %I.%I including defaults including constraints'
															'\n				)'															
															'\n			;'
															'\n			alter table'
															'\n				%I.%%I'
															'\n			add constraint'
															'\n				chk_%%I$%s check (%s %%s)'
															'\n			$ddl$'
															'\n			, chunk.new_partition'
															'\n			, chunk.new_partition'
															'\n			, chunk.new_partition'
															'\n			, chunk.partition_bound_spec'
															'\n		)'
															'\n		, E'';\\n'''
															'\n	) filter ('
															'\n		where '
															'\n			chunk.new_partition_table_id is null'
															'\n	) as new_partition_table_creating'
															'\n	, string_agg('
															'\n		format($ddl$'
															'\n			truncate'
															'\n				%I.%%I'
															'\n			$ddl$'
															'\n			, chunk.new_partition'
															'\n		)'
															'\n		, E'';\\n'''
															'\n	) filter ('
															'\n		where '
															'\n			chunk.new_partition_table_id is not null'
															'\n	) as new_partition_table_truncating'
															'\n	, string_agg('
															'\n		format($dml$'
															'\n			%s'
															'\n			$dml$'
															'\n			%s, chunk.new_partition'
															'\n			, chunk.arr'
															'\n			, chunk.type%s'
															'\n		)'
															'\n		, E'';\\n'''
															'\n	) as new_partition_filling'
															'\n	, string_agg('
															'\n		format($dml$'
															'\n			insert into'
															'\n				${stagingSchemaName}.materialized_view_partition('
															'\n					meta_view_id'
															'\n					, partition_id'
															'\n					, current_table_id'
															'\n					, shadow_table_id'
															'\n					, partition_bound_spec'
															'\n					, refresh_time'
															'\n				)'
															'\n			values('
															'\n				%%s'
															'\n				, %%L'
															'\n				, coalesce('
															'\n					nullif(%%L, '''')::${type.system_object_id}'
															'\n					, ('
															'\n						select'
															'\n							t.obj_id'
															'\n						from'
															'\n							${mainSchemaName}.v_sys_obj t'
															'\n						where'
															'\n							t.obj_schema = %L'
															'\n							and t.obj_name = %%L'
															'\n							and t.obj_class = ''relation'''
															'\n					)'
															'\n				)'
															'\n				, nullif(%%L, '''')::${type.system_object_id}'
															'\n				, %%L'
															'\n				, ${mainSchemaName}.f_current_timestamp()'
															'\n			)'
															'\n			on conflict (meta_view_id, partition_id)'
															'\n				do update set'
															'\n					current_table_id = excluded.current_table_id'
															'\n					, shadow_table_id = excluded.shadow_table_id'
															'\n					, partition_bound_spec = excluded.partition_bound_spec'
															'\n					, refresh_time = excluded.refresh_time'
															'\n			$dml$'
															'\n			, l_meta_view_id'
															'\n			, chunk.id'
															'\n			, chunk.new_partition_table_id'
															'\n			, chunk.new_partition'
															'\n			, chunk.old_partition_table_id'
															'\n			, chunk.partition_bound_spec'
															'\n		)'
															'\n		, E'';\\n'''
															'\n	) as partition_registering'
															'\ninto'
															'\n	l_chunk_rec'
															'\nfrom ('
															'\n	select'
															'\n		chunk.id'
															'\n		, chunk.arr'
															'\n		, chunk.type'
															'\n		, format('
															'\n			$expr$in (%%L::%%s)$expr$'
															'\n			, chunk.id'
															'\n			, chunk.type'
															'\n		) as partition_bound_spec'
															'\n		, chunk.sys_name'
															'\n		, chunk.schema_name'
															'\n		, chunk.table_name'
															'\n		, case'
															'\n			when partition0.partition_table_name is null then chunk.partition_table0'
															'\n			else chunk.partition_table1'
															'\n		end as new_partition'
															'\n		, case'
															'\n			when partition0.partition_table_name is null then table0.obj_id'
															'\n			else table1.obj_id'
															'\n		end as new_partition_table_id'
															'\n		, case'
															'\n			when partition0.partition_table_name is null then table1.obj_id'
															'\n			else table0.obj_id'
															'\n		end as old_partition_table_id'
															'\n	from ('
															'\n		select'
															'\n			c.id'
															'\n			, array[c.id] as arr'
															'\n			, pg_catalog.pg_typeof(c.id) as type'
															'\n			, c.sys_name'
															'\n			, c.schema_name'
															'\n			, c.table_name'
															'\n			, concat_ws('
															'\n			 	''_'''
															'\n			 	, c.table_name'
															'\n			 	, c.sys_name'
															'\n			 	, ''0'''
															'\n			)::name as partition_table0'
															'\n			, concat_ws('
															'\n				''_'''
															'\n			 	, c.table_name'
															'\n			 	, c.sys_name'
															'\n			 	, ''1'''
															'\n			)::name as partition_table1'
															'\n		from ('
															'\n			select'
															'\n				chunk.id'
															'\n				, ${mainSchemaName}.f_valid_system_name('
															'\n					i_raw_name => chunk.id::text'
															'\n					, i_is_considered_as_whole_name => false'
															'\n				) as sys_name'
															'\n				, %L::name as schema_name'
															'\n				, %L::name as table_name'
															'\n			from'
															'\n				unnest(%s) chunk(id)'
															'\n		) c'
															'\n	) chunk'
															'\n	left join ${mainSchemaName}.v_sys_obj table0'
															'\n		on table0.obj_schema = chunk.schema_name'
															'\n		and table0.obj_name = chunk.partition_table0'
															'\n		and table0.obj_class = ''relation'''
															'\n	left join ${mainSchemaName}.v_sys_table_partition partition0'
															'\n		on partition0.schema_name = chunk.schema_name'
															'\n		and partition0.table_name = chunk.table_name'
															'\n		and partition0.partition_table_name = chunk.partition_table0'
															'\n		and partition0.partition_schema_name = chunk.schema_name'
															'\n	left join ${mainSchemaName}.v_sys_obj table1'
															'\n		on table1.obj_schema = chunk.schema_name'
															'\n		and table1.obj_name = chunk.partition_table1'
															'\n		and table1.obj_class = ''relation'''
															'\n	left join ${mainSchemaName}.v_sys_table_partition partition1'
															'\n		on partition1.schema_name = chunk.schema_name'
															'\n		and partition1.table_name = chunk.table_name'
															'\n		and partition1.partition_table_name = chunk.partition_table1'
															'\n		and partition1.partition_schema_name = chunk.schema_name'
															'\n) chunk'															
															'\n;'
															'\n'
															'\nif l_chunk_rec.new_partition_table_creating is not null then'
															'\n execute'
															'\n 	l_chunk_rec.new_partition_table_creating'
															'\n ;'
															'\nelsif l_chunk_rec.new_partition_table_truncating is not null then'
															'\n execute'
															'\n 	l_chunk_rec.new_partition_table_truncating'
															'\n ;'
															'\nend if'
															'\n;'
															'\nexecute'
															'\n	l_chunk_rec.new_partition_filling'
															'\n;'
															'\nexecute'
															'\n	l_chunk_rec.partition_registering'
															'\n;'
															, i_view_rec.schema_name
															, i_view_rec.schema_name
															, i_view_rec.internal_name
															, i_view_rec.schema_name
															, i_view_rec.mv_emulation_chunking_field
															, i_view_rec.mv_emulation_chunking_field
															, i_view_rec.schema_name
															, ${mainSchemaName}.f_indent_text(
																i_text =>
																	concat_ws(
																		E'\n;\n'
																		, case 
																			when i_view_rec.mv_emulation_chunk_row_limit is not null then
																				format(
																					E'do $$'
																					'\ndeclare'
																					'\n	l_row_limit bigint := %%s;'
																					'\n	l_row_offset bigint := 0;'
																					'\nbegin'
																					'\n	<<insertion_in_parts>>'
																					'\n	loop' 
																					'\n		insert into'
																					'\n			%I.%%I'
																					'\n		select'
																					'\n			*'
																					'\n		from'
																					'\n			%I.%I('
																					'\n				%s => %%L::%%s[]'
																					'\n				, i_row_limit => l_row_limit'
																					'\n				, i_row_offset => l_row_offset'
																					'\n			)'
																					'\n		;'
																					'\n		exit insertion_in_parts when not found'
																					'\n		;'
																					'\n		l_row_offset := l_row_offset + l_row_limit'
																					'\n		;'
																					'\n	end loop insertion_in_parts'
																					'\n	;'
																					'\nend'
																					'\n$$'
																					, i_view_rec.schema_name
																					, i_view_rec.schema_name
																					, i_view_rec.mv_emulation_table_func_name
																					, i_view_rec.mv_emulation_refresh_proc_param
																				)
																			else
																				format(
																					E'insert into'
																					'\n	%I.%%I'
																					'\nselect'
																					'\n	*'
																					'\nfrom'
																					'\n	%I.%I('
																					'\n		%s => %%L::%%s[]'
																					'\n	)'
																					, i_view_rec.schema_name
																					, i_view_rec.schema_name
																					, i_view_rec.mv_emulation_table_func_name
																					, i_view_rec.mv_emulation_refresh_proc_param
																				)
																		end
																		, l_chunk_invalidation_script
																	)
																, i_indentation_level => 3
															)
															, case 
																when i_view_rec.mv_emulation_chunk_row_limit is not null then
																	${mainSchemaName}.f_indent_text(
																		i_text =>
																			E', l_row_limit\n'
																		, i_indentation_level => 3
																	)
																else
																	''
															end
															, l_chunk_invalidation_script_subst
															, i_view_rec.schema_name
															, i_view_rec.schema_name
															, i_view_rec.internal_name
															, i_view_rec.mv_emulation_refresh_proc_param
														)												
													else
														format(
															E'\n\ndelete from'
															'\n	%I.%I'
															'\nwhere'
															'\n	%s = any(%s)'
															'\n	or %s is null'
															'\n;'
															, i_view_rec.schema_name
															, i_view_rec.internal_name
															, i_view_rec.mv_emulation_chunking_field
															, i_view_rec.mv_emulation_refresh_proc_param
															, i_view_rec.mv_emulation_chunking_field
														) 
														|| E'\n\n'
														|| case 
															when i_view_rec.mv_emulation_chunk_row_limit is not null then
																format(	
																	E'<<insertion_in_parts>>'
																	'\nloop' 
																	'\n	insert into'
																	'\n		%I.%I'
																	'\n	select'
																	'\n		*'
																	'\n	from'
																	'\n		%I.%I('
																	'\n			%s => %s'
																	'\n			, i_row_limit => l_row_limit'
																	'\n			, i_row_offset => l_row_offset'
																	'\n		)'
																	'\n	;'
																	'\n	exit insertion_in_parts when not found'
																	'\n	;'
																	'\n	l_row_offset := l_row_offset + l_row_limit'
																	'\n	;'
																	'\nend loop insertion_in_parts'
																	'\n;'
																	, i_view_rec.schema_name
																	, i_view_rec.internal_name
																	, i_view_rec.schema_name
																	, i_view_rec.mv_emulation_table_func_name
																	, i_view_rec.mv_emulation_refresh_proc_param												
																	, i_view_rec.mv_emulation_refresh_proc_param
																)																	
															else 
																format(		
																	E'insert into'
																	'\n	%I.%I'
																	'\nselect'
																	'\n	*'
																	'\nfrom'
																	'\n	%I.%I('
																	'\n		%s => %s'
																	'\n	)'
																	'\n;'
																	, i_view_rec.schema_name
																	, i_view_rec.internal_name
																	, i_view_rec.schema_name
																	, i_view_rec.mv_emulation_table_func_name
																	, i_view_rec.mv_emulation_refresh_proc_param												
																	, i_view_rec.mv_emulation_refresh_proc_param
																)
														end
												end			
												|| case 
													when i_view_rec.is_mv_emulation_chunk_validated then
														format(
															E'\n\ninsert into'
															'\n	%I.%I_chunk('
															'\n		%s'
															'\n		, refresh_time'
															'\n	)'
															'\nselect'
															'\n	id'
															'\n	, ${mainSchemaName}.f_current_timestamp()'
															'\nfrom'
															'\n	unnest(%s) chunk(id)'
															'\non conflict (%s)'
															'\n	do nothing'
															'\n;'
															, i_view_rec.schema_name
															, i_view_rec.internal_name
															, i_view_rec.mv_emulation_chunking_field
															, i_view_rec.mv_emulation_refresh_proc_param
															, i_view_rec.mv_emulation_chunking_field
														)
													else ''
												end
											, i_indentation_level => 2
										)
									)
								)
						end
					)
				else
					regexp_replace(
						t.sttmnt
					 	, 'materialized view'
					 	, 'table'
					 	, 'i'
					)
			end as ddl_sttmnt
			, (t.view_query is not null) as is_matview_query
		from (
			select
				t.obj_class
				, t.obj_name
				, t.view_query
				, t.sttmnt
				, t.ordinal_num
			 	, array_agg(t.chunking_filter_marker) as chunking_filter_marker
			 	, array_agg(t.chunking_filter_expr) as chunking_filter_expr
				, t.chunk_row_limit_marker
				, t.chunk_row_limit_expr
			from (
				select 
					obj_def.obj_class
					, obj_def.obj_name
					, case 
						when obj_def.obj_class = 'materialized view' then
							obj_def.obj_body
					end as view_query
					, obj_def.ordinal_num
					, case 
						when obj_def.obj_body is null
							and target_obj.obj_body is not null
							and target_obj.obj_class <> 'materialized view' 
						then
							case 
								when target_obj.obj_class in ('index', 'unique index') then
									format(	
										'drop index if exists %I.%I'
										, i_view_rec.schema_name
										, target_obj.obj_name
									)
								when target_obj.obj_class = 'comment on column' then
									format(	
										E'do $$'
										'\nbegin'
										'\n	if exists ('
										'\n		select'
										'\n			1'
										'\n		from'
										'\n			information_schema.columns'
										'\n		where'
										'\n			table_schema = %L'
										'\n			and table_name = %L'
										'\n			and column_name = %L'
										'\n	)'
										'\n	then'
										'\n		comment on column %I.%I.%s is null'
										'\n		;'
										'\n	end if'
										'\n	;'
										'\nend'
										'\n$$'
										'\n;'	
										, i_view_rec.schema_name
										, i_view_rec.internal_name
										, target_obj.obj_name
										, i_view_rec.schema_name
										, i_view_rec.internal_name
										, target_obj.obj_name
									)
								when target_obj.obj_class = 'comment on materialized view' then
									format(	
										'comment on table %I.%I is null'
										, i_view_rec.schema_name
										, i_view_rec.internal_name
									)
							end
						when obj_def.obj_body is not null
							and target_obj.obj_body is not null
							and target_obj.obj_class in ('index', 'unique index') 
						then
							concat_ws(
								E'\n;'
								, format(	
									'drop index if exists %I.%I'
									, i_view_rec.schema_name
									, target_obj.obj_name
								)
								, obj_def.sttmnt
							)
						else 
							obj_def.sttmnt
					end as sttmnt
					, case 
						when obj_def.obj_class in ('index', 'unique index') then
							(
								target_obj.obj_name is null 
								or (
									obj_def.obj_name = target_obj.obj_name
									and regexp_replace(obj_def.obj_body, '\s', '', 'g') <> target_obj.obj_body
								)
								or obj_def.obj_class <> target_obj.obj_class
							)	
						when obj_def.obj_class = 'comment on column' then
							(
								target_obj.obj_name = obj_def.obj_name
								and (
									nullif(obj_def.obj_body, target_obj.obj_body) is not null 
									or (
										obj_def.obj_body is null 
										and target_obj.obj_body is not null
									)
								)
							)
						when obj_def.obj_class = 'comment on materialized view' then
							(
								nullif(obj_def.obj_body, target_obj.obj_body) is not null 
								or (
									obj_def.obj_body is null 
									and target_obj.obj_body is not null
								)
							)
						else 
							true
					end as must_be_executed
				 	, obj_def.chunking_filter_marker
				 	, obj_def.chunking_filter_expr
					, obj_def.chunk_row_limit_marker
					, obj_def.chunk_row_limit_expr
				from (
					select 
						sttmnt.expr[1] as sttmnt
						, sttmnt.ordinal_num
						, obj_def.class as obj_class
						, substring(
							lower(obj_def.name[1])
							, 1
							, ${mainSchemaName}.f_system_name_max_length()
						) as obj_name					
						, obj_def.body[1] as obj_body
					 	, chunking_filter_marker[1] as chunking_filter_marker
					 	, chunking_filter_expr[1] as chunking_filter_expr
						, chunk_row_limit_marker[1] as chunk_row_limit_marker
						, chunk_row_limit_expr[1] as chunk_row_limit_expr
					from  
						regexp_matches(
							i_view_rec.query
							, '(.+?);'  
							, 'g'
						) with ordinality as sttmnt(expr, ordinal_num)
						left join lateral (
							values (
									'materialized view'
									, null::name[]
									, regexp_match(
										sttmnt.expr[1]
										, '\s*create materialized view\s+.+?as\s+(.+?)(?:\s*(?:with\s+no\s+data|with\s+data)\s*)?' 
										, 'i'
									)
								)
								, (
									'index'
									, regexp_match(
										sttmnt.expr[1]
										, '\s*create\s+index\s+(.+?)\s+on' 
										, 'i'
									)
									, regexp_match(
										sttmnt.expr[1]
										, '\s*create\s+index\s+.+?\(\s*(.+?)\s*\)' 
										, 'i'
									)
								)
								, (
									'unique index'
									, regexp_match(
										sttmnt.expr[1]
										, '\s*create\s+unique\s+index\s+(.+?)\s+on' 
										, 'i'
									)
									, regexp_match(
										sttmnt.expr[1]
										, '\s*create\s+unique\s+index\s+.+?\(\s*(.+?)\s*\)' 
										, 'i'
									)
								)
								, (
									'comment on materialized view'
									, null::name[]
									, regexp_match(
										sttmnt.expr[1]
										, '\s*comment\s+on\s+materialized\s+view\s+.+?is\s*''(.+?)''' 
										, 'i'
									)
								)
								, (
									'comment on column'
									, regexp_match(
										sttmnt.expr[1]
										, '\s*comment\s+on\s+column\s+.+?"*([^\.]+?)"*\s+is' 
										, 'i'
									)
									, regexp_match(
										sttmnt.expr[1]
										, '\s*comment\s+on\s+column\s+.+?is\s*''(.+?)''' 
										, 'i'
									)
								)
						) as obj_def(
							class
							, name
							, body
						)
						on obj_def.body is not null						
					left join lateral 
						regexp_matches(
							obj_def.body[1]
							, '(\/\*\s*\#chunking_filter\:\s*.+?\s*\*\/){1,1}?' 
							, 'ig'
						) as chunking_filter_marker
						on obj_def.class = 'materialized view'
					cross join lateral
						regexp_match(
							chunking_filter_marker[1]
							, '\/\*\s*\#chunking_filter\:\s*(.+?)\s*\*\/' 
							, 'i'
						) as chunking_filter_expr
					left join lateral
						regexp_match(
							obj_def.body[1]
							, '(\/\*\s*\#chunk_row_limit\:\s*.+?\s*\*\/){1,1}?' 
							, 'i'
						) as chunk_row_limit_marker
						on obj_def.class = 'materialized view'
					cross join lateral
						regexp_match(
							chunk_row_limit_marker[1]
							, '\/\*\s*\#chunk_row_limit\:\s*(.+?)\s*\*\/' 
							, 'i'
						) as chunk_row_limit_expr
				) obj_def
				full join (
					select 
						case 
							when i.indisunique then 'unique index'
							else 'index'
						end as obj_class
						, target_index.relname as obj_name
						, index_col.index_columns as obj_body
					from
						pg_catalog.pg_class target_table
					join pg_catalog.pg_namespace n 
						on n.oid = target_table.relnamespace
						and n.nspname = i_view_rec.schema_name
					join pg_catalog.pg_index i
						on i.indrelid = target_table.oid 
					join pg_catalog.pg_class target_index
						on target_index.oid = i.indexrelid
					left join lateral (
						select 
							string_agg(
								a.attname
								, ',' 
								order by 
									array_position(i.indkey, a.attnum)
							) as index_columns
						from 
							pg_catalog.pg_attribute a
						where
							a.attrelid = i.indrelid
							and a.attnum = any(i.indkey)
					) index_col 
						on true
					where 
						target_table.relname = i_view_rec.internal_name
					union all 
					select 
						'comment on materialized view' as obj_class
						, null::name as obj_name
						, d.description as obj_body
					from
						pg_catalog.pg_class target_table
					join pg_catalog.pg_namespace n 
						on n.oid = target_table.relnamespace
						and n.nspname = i_view_rec.schema_name
					join pg_catalog.pg_description d 
						on d.objoid = target_table.oid
						and d.classoid = 'pg_class'::regclass
						and d.objsubid = 0
					where 
						target_table.relname = i_view_rec.internal_name
					union all 
					select 
						'comment on column' as obj_class
						, a.attname as obj_name
						, d.description as obj_body
					from
						pg_catalog.pg_class target_table
					join pg_catalog.pg_namespace n 
						on n.oid = target_table.relnamespace
						and n.nspname = i_view_rec.schema_name
					join pg_catalog.pg_attribute a
						on a.attrelid = target_table.oid
						and a.attnum > 0
					join pg_catalog.pg_description d 
						on d.objoid = target_table.oid
						and d.classoid = 'pg_class'::regclass
						and d.objsubid = a.attnum
					where 
						target_table.relname = i_view_rec.internal_name
				) target_obj
					on obj_def.obj_class = target_obj.obj_class
					and obj_def.obj_name is not distinct from target_obj.obj_name			
			) t
			where 
				t.must_be_executed
			group by 
				t.obj_class
				, t.obj_name
				, t.view_query
				, t.sttmnt
				, t.ordinal_num
				, t.chunk_row_limit_marker
				, t.chunk_row_limit_expr
		) t
		, coalesce(
			${stagingSchemaName}.f_substitute(
				i_text => t.view_query
				, i_keys => t.chunking_filter_marker
				, i_values => t.chunking_filter_expr
				, i_quote_value => false
			)
			, ${mainSchemaName}.f_indent_text(
				i_text => 
					format(
						E'select *'
						'\nfrom ('
						'\n\t%s'
						'\n) t'
						'\nwhere'
						'\n\t%s = any(%s)'
						, t.view_query
						, i_view_rec.mv_emulation_chunking_field
						, i_view_rec.mv_emulation_refresh_proc_param
					)
				, i_indentation_level => 1
			)
		) as query_with_chunking_filter
		, coalesce(
			replace(
				query_with_chunking_filter
				, chunk_row_limit_marker
				, chunk_row_limit_expr
			)
			, query_with_chunking_filter
			|| case 
				when chunk_row_limit_marker is not null and i_view_rec.has_unique_index and t.view_query not ilike '%order by%' then 
					format(
						E'\norder by'
						'\n	%s'
						, i_view_rec.unique_index_columns
					)
					|| case 
						when i_view_rec.mv_emulation_chunking_field is null then
							E'\nlimit'
							'\n	l_row_limit'
							'\noffset'
							'\n	l_row_offset'
						else
							E'\nlimit'
							'\n	i_row_limit'
							'\noffset'
							'\n	i_row_offset'
					end
				else 
					''
			end
		) as target_query
		order by 
			t.ordinal_num
	) 
	loop
		raise notice 
			'%'
			, l_sttmnt.ddl_sttmnt
		;
		execute
			l_sttmnt.ddl_sttmnt
		;
	
		if l_sttmnt.is_matview_query then 
			l_is_matview_recognized := true;
		end if;
	end loop;

	if not l_is_matview_recognized then
		raise 'The materialized view %.% is not defined as it should be', i_view_rec.schema_name, i_view_rec.internal_name; 
	end if;
end
$procedure$;	

comment on procedure p_build_matview_emulation(
	${mainSchemaName}.v_meta_view
) is 'Сгенерировать эмуляцию материализованного представления';
