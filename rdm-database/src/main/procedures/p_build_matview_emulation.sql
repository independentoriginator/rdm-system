create or replace procedure p_build_matview_emulation(
	i_view_rec ${mainSchemaName}.v_meta_view
)
language plpgsql
as $procedure$
declare 
	l_sttmnt record;
	l_is_matview_recognized boolean := false;
begin
	for l_sttmnt in (
		select 
			case 
				when view_query[1] is not null then
					concat_ws(
						E';\n'
						-- creation of a table that will replace the materialized view  
						, case 
							when i_view_rec.mv_emulation_with_partitioning 
								and i_view_rec.mv_emulation_chunking_field is not null
							then
								format('
									create temp table %I_%I 
									as 
									select * 
									from (%s) t 
									where false
									; 
									create table %I.%I(like %I_%I)
									partition by list (%s)
									;
									drop table %I_%I
									;
									'
									, i_view_rec.internal_name
									, i_view_rec.schema_name
									, view_query[1]
									, i_view_rec.schema_name
									, i_view_rec.internal_name
									, i_view_rec.internal_name
									, i_view_rec.schema_name
									, i_view_rec.mv_emulation_chunking_field
									, i_view_rec.internal_name
									, i_view_rec.schema_name
								)
							else 
								format('
									create table %I.%I 
									as 
									select * 
									from (%s) t 
									where false
									'
									, i_view_rec.schema_name
									, i_view_rec.internal_name
									, view_query[1]
								)
						end
						-- creation of a service table that will contain a list of filled chunks
						, case 
							when i_view_rec.is_mv_emulation_chunk_validated then
								format('
									create table %I.%I_chunk
									as 
									select %s
									from %I.%I 
									where false
									;
									alter table %I.%I_chunk 
										add primary key(%s)
									'
									, i_view_rec.schema_name
									, i_view_rec.internal_name
									, i_view_rec.mv_emulation_chunking_field
									, i_view_rec.schema_name
									, i_view_rec.internal_name
									, i_view_rec.schema_name
									, i_view_rec.internal_name
									, i_view_rec.mv_emulation_chunking_field
								)
						end
						-- generation of a refresh procedure for the emulated materialized view 
						, case 
							when i_view_rec.mv_emulation_chunking_field is null then
								format(
									E'create or replace procedure %I.%I()'
									'\nlanguage plpgsql'
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
																i_text => view_query[1]
																, i_indentation_level => 1
															)																
														)
													else
														format(
															E'insert into %I.%I\n%s\n;'
															, i_view_rec.schema_name
															, i_view_rec.internal_name
															, view_query[1]
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
										E'create temp view tv_%I_%I as'
										'\nselect' 
										'\n	array('
										'\n		select %s from %I.%I limit 0'
										'\n	) as arr_%s'
										'\n;'
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
										'\nlanguage sql'
										'\nstable'
										'\nparallel safe'									
										'\nas $routine$'
										'\n	%s'
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
										, target_query
 									)
									, format(
										E'create or replace procedure %I.%I('
										'\n\t%s tv_%I_%I.arr_%s%%type = null'
										'\n)'
										'\nlanguage plpgsql'
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
										'\n					) c'
										'\n					$sql$'
										'\n				, i_context_id => ''%I.%I''::regproc::integer'
										'\n			)'
										'\n		;'
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
														E'\n	l_chunk_rec record;'
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
														, i_indentation_level => 7
													)
												)
											else ''
										end
										, i_view_rec.schema_name
										, i_view_rec.mv_emulation_refresh_proc_name
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
															'\n				chk_%%I$%s check (%s in (%%L::%%s))'
															'\n			;'
															'\n			$ddl$'
															'\n			, chunk.new_partition'
															'\n			, chunk.new_partition'
															'\n			, chunk.new_partition'
															'\n			, chunk.id'
															'\n			, pg_catalog.pg_typeof(chunk.id)'
															'\n		)'
															'\n		, E'';\\n'''
															'\n	) filter ('
															'\n		where '
															'\n			not chunk.is_new_partition_table_exists'
															'\n	) as new_partition_table_creating'
															'\n	, string_agg('
															'\n		format($dml$'
															'\n			%s'
															'\n			$dml$'
															'\n			%s, chunk.new_partition'
															'\n			, array[chunk.id]'
															'\n			, pg_catalog.pg_typeof(chunk.id)'
															'\n		)'
															'\n		, E'';\\n'''
															'\n	) as new_partition_filling'
															'\n	, string_agg($ddl$'
															'\n		lock table'
															'\n			%I.%I'
															'\n		in access exclusive mode'
															'\n		;'
															'\n		$ddl$'
															'\n		, E'';\\n'''
															'\n	) as parent_table_locking'
															'\n	, string_agg('
															'\n		format($ddl$'
															'\n			alter table'
															'\n				%I.%I'
															'\n			detach partition'
															'\n				%I.%%I'
															'\n			;'
															'\n			$ddl$'
															'\n			, chunk.old_partition'
															'\n		)'
															'\n		, E'';\\n'''
															'\n	) filter ('
															'\n		where '
															'\n			chunk.old_partition is not null'
															'\n	) as old_partition_detaching'
															'\n	, string_agg('
															'\n		format($ddl$'
															'\n			alter table'
															'\n				%I.%I'
															'\n			attach partition %I.%%I'
															'\n				for values in (%%L::%%s)'	
															'\n			;'
															'\n			$ddl$'
															'\n			, chunk.new_partition'
															'\n			, chunk.id'
															'\n			, pg_catalog.pg_typeof(chunk.id)'
															'\n		)'
															'\n		, E'';\\n'''
															'\n	) as new_partition_attaching'
															'\n	, string_agg('
															'\n		format($ddl$'
															'\n			truncate'
															'\n				%I.%%I'
															'\n			;'
															'\n			$ddl$'
															'\n			, chunk.old_partition'
															'\n		)'
															'\n		, E'';\\n'''
															'\n	) filter ('
															'\n		where '
															'\n			chunk.old_partition is not null'
															'\n	) as old_partition_truncating'
															'\ninto'
															'\n	l_chunk_rec'
															'\nfrom ('
															'\n	select'
															'\n		chunk.id'
															'\n		, chunk.sys_name'
															'\n		, chunk.schema_name'
															'\n		, chunk.table_name'
															'\n		, case'
															'\n			when partition0.partition_table_name is null then chunk.partition_table0'
															'\n			else chunk.partition_table1'
															'\n		end as new_partition'
															'\n		, case'
															'\n			when partition0.partition_table_name is null then (table0.obj_id is not null)'
															'\n			else (table1.obj_id is not null)'
															'\n		end as is_new_partition_table_exists'
															'\n		, coalesce('
															'\n			partition0.partition_table_name'
															'\n			, partition1.partition_table_name'
															'\n		) as old_partition'															
															'\n		, case'
															'\n			when partition0.partition_table_name is not null then (table0.obj_id is not null)'
															'\n			else (table1.obj_id is not null)'
															'\n		end as is_old_partition_table_exists'
															'\n	from ('
															'\n		select'
															'\n			c.id'
															'\n			, c.sys_name'
															'\n			, c.schema_name'
															'\n			, c.table_name'
															'\n			, c.table_name || c.sys_name || ''_0''::name as partition_table0'
															'\n			, c.table_name || c.sys_name || ''_1''::name as partition_table1' 
															'\n		from ('
															'\n			select'
															'\n				chunk.id'
															'\n				, ${mainSchemaName}.f_valid_system_name('
															'\n					i_raw_name => chunk.id::text'
															'\n					, i_is_considered_as_whole_name => false'
															'\n				) as sys_name'
															'\n				, ''%I''::name as schema_name'
															'\n				, ''%I''::name as table_name'
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
															'\nif l_chunk_rec.new_partition_table_creating is not null then '
															'\n execute'
															'\n 	l_chunk_rec.new_partition_table_creating'
															'\n ;'
															'\nend if'
															'\n;'
															'\nexecute'
															'\n	l_chunk_rec.new_partition_filling'
															'\n;'
															'\nexecute'
															'\n	l_chunk_rec.parent_table_locking'
															'\n;'
															'\nif l_chunk_rec.old_partition_detaching is not null then '
															'\n execute'
															'\n 	l_chunk_rec.old_partition_detaching'
															'\n	;'
															'\nend if'
															'\n;'
															'\nexecute'
															'\n	l_chunk_rec.new_partition_attaching'
															'\n;'
															'\nif l_chunk_rec.old_partition_truncating is not null then '
															'\n execute'
															'\n 	l_chunk_rec.old_partition_truncating'
															'\n	;'
															'\nend if'
															'\n;'
															, i_view_rec.schema_name
															, i_view_rec.schema_name
															, i_view_rec.internal_name
															, i_view_rec.schema_name
															, i_view_rec.mv_emulation_chunking_field
															, i_view_rec.mv_emulation_chunking_field
															, ${mainSchemaName}.f_indent_text(
																i_text =>
																	case 
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
															, i_view_rec.schema_name
															, i_view_rec.internal_name
															, i_view_rec.schema_name
															, i_view_rec.internal_name
															, i_view_rec.schema_name
															, i_view_rec.schema_name
															, i_view_rec.internal_name
															, i_view_rec.schema_name
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
															'\n;'
															, i_view_rec.schema_name
															, i_view_rec.internal_name
															, i_view_rec.mv_emulation_chunking_field
															, i_view_rec.mv_emulation_refresh_proc_param												
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
															'\n	)'
															'\nselect'
															'\n	c.id'
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
						-- generation of a trigger function for the master table within the registered chunk dependence
						, case 
							when i_view_rec.is_mv_emulation_chunk_validated is null then (
								select 
									string_agg(
										format(
											E'create or replace function %I.trf_%I_%s_invalidate()'
											'\nreturns trigger'
											'\nlanguage plpgsql'
											'\nas $$'
											'\nbegin'
											'\n	delete from'
											'\n		%I.%I_chunk chunk'
											'\n	where'
											'\n		exists ('
											'\n			select'
											'\n				1'
											'\n			from'
											'\n				old_table t'
											'\n			where'
											'\n				t.%s = chunk.%s'
											'\n		)'
											'\n		or exists ('
											'\n			select'
											'\n				1'
											'\n			from'
											'\n				new_table t'
											'\n			where'
											'\n				t.%s = chunk.%s'
											'\n		)'
											'\n	;'
											'\n	return null'
											'\n	;'
											'\nend'
											'\n$$;'
											'\ncreate trigger tr_%I_after'
											'\nafter insert or update or delete'
											'\non %I.%I'
											'\nreferencing new table as new_table old table as old_table'
											'\nfor each statement'
											'\nexecute function %I.trf_%I_%s_invalidate();'	
											, dep.master_table_schema
											, dep.master_table_name
											, dep.dependent_view_abbr
											, i_view_rec.schema_name
											, i_view_rec.internal_name
											, dep.master_chunk_field
											, i_view_rec.mv_emulation_chunking_field
											, dep.master_chunk_field
											, i_view_rec.mv_emulation_chunking_field
											, dep.master_table_name
											, dep.master_table_schema
											, dep.master_table_name
											, dep.master_table_schema
											, dep.master_table_name
											, dep.dependent_view_abbr
										)
										, E';\n'
									)
								from (
									select 
										coalesce(mv.schema_name, mt.schema_name) as master_table_schema
										, coalesce(mv.internal_name, mt.internal_name) as master_table_name
										, ${mainSchemaName}.f_abbreviate_name(
											i_name =>
												format(
													'%I_%I'													
													, i_view_rec.schema_name
													, i_view_rec.internal_name
												)
											, i_adjust_to_max_length => true
											, i_max_length => 
												${mainSchemaName}.f_system_name_max_length()
												- length(
													format(
														'trf_%I__invalidate'
														, coalesce(mv.internal_name, mt.internal_name)
													)
												)				
										) as dependent_view_abbr
										, dep.master_chunk_field
									from									
										${mainSchemaName}.meta_view_chunk_dependency dep
									left join ${mainSchemaName}.v_meta_view mv
										on mv.id = dep.master_view_id
									left join ${mainSchemaName}.v_meta_type mt
										on mt.id = dep.master_type_id
									where 
										dep.view_id = i_view_rec.id
								) dep
							)
						end
					)
				else
					regexp_replace(
						sttmnt[1]
					 	, 'materialized view'
					 	, 'table'
					 	, 'i'
					)
			end as ddl_sttmnt
			, (view_query[1] is not null) is_matview_query
		from 
			regexp_matches(
				i_view_rec.query
				, '(.+?);'  
				, 'g'
			) as sttmnt
			, regexp_match(
				sttmnt[1]
				, '\s*create materialized view\s+.+?as\s+(.+?)(?:\s*(?:with\s+no\s+data|with\s+data)\s*)?' 
				, 'i'
			) as view_query
			, regexp_match(
				view_query[1]
				, '(\/\*\s*\#chunking_filter\:\s*.+?\s*\*\/){1,1}?' 
				, 'i'
			) as chunking_filter_marker
			, regexp_match(
				chunking_filter_marker[1]
				, '\/\*\s*\#chunking_filter\:\s*(.+?)\s*\*\/' 
				, 'i'
			) as chunking_filter_expr
			, regexp_match(
				view_query[1]
				, '(\/\*\s*\#chunk_row_limit\:\s*.+?\s*\*\/){1,1}?' 
				, 'i'
			) as chunk_row_limit_marker
			, regexp_match(
				chunk_row_limit_marker[1]
				, '\/\*\s*\#chunk_row_limit\:\s*(.+?)\s*\*\/' 
				, 'i'
			) as chunk_row_limit_expr
			, coalesce(
				replace(
					view_query[1]
				 	, chunking_filter_marker[1]
				 	, chunking_filter_expr[1]
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
							, view_query[1]
							, i_view_rec.mv_emulation_chunking_field
							, i_view_rec.mv_emulation_refresh_proc_param
						)
					, i_indentation_level => 1
				)
			) as query_with_chunking_filter
			, coalesce(
				replace(
					query_with_chunking_filter
					, chunk_row_limit_marker[1]
					, chunk_row_limit_expr[1]
				)
				, query_with_chunking_filter
				|| case 
					when i_view_rec.has_unique_index and view_query[1] not ilike '%order by%' then 
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
		raise 'The materialized view %.% is not defined as it expected', i_view_rec.schema_name, i_view_rec.internal_name; 
	end if;
end
$procedure$;	

comment on procedure p_build_matview_emulation(
	${mainSchemaName}.v_meta_view
) is 'Сгенерировать эмуляцию материализованного представления';
