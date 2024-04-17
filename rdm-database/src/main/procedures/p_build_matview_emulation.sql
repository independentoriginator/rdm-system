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
						, case 
							when i_view_rec.mv_emulation_chunking_field is null then
								format(
									E'create or replace procedure %I.%I()'
									'\nlanguage plpgsql'
									'\nas $routine$'
									'\nbegin'
									'\n\t%s'
									'\nend'
									'\n$routine$;'
									, i_view_rec.schema_name
									, i_view_rec.mv_emulation_refresh_proc_name
									, ${mainSchemaName}.f_indent_text(
										i_text => 									
											format(
												E'perform pg_catalog.pg_advisory_xact_lock(''%I.%I''::regclass::bigint);'
												'\n\ntruncate %I.%I;'
												'\n\ninsert into %I.%I\n%s\n;'
												, i_view_rec.schema_name
												, i_view_rec.internal_name
												, i_view_rec.schema_name
												, i_view_rec.internal_name
												, i_view_rec.schema_name
												, i_view_rec.internal_name
												, view_query[1]
											)
										, i_indentation_level => 1		
									)
								)
							else
								format(
									E'create temp view tv_%I_%I as'
									'\nselect' 
									'\n	array('
									'\n		select %s from %I.%I limit 0'
									'\n	) as arr_%s'
									'\n;'
									'\ncreate or replace function %I.%I('
									'\n	%s tv_%I_%I.arr_%s%%type'
									'\n)'
									'\nreturns setof %I.%I'
									'\nlanguage sql'
									'\nstable'
									'\nparallel safe'									
									'\nas $routine$'
									'\n	%s'
									'\n$routine$;'									
									'\n;'
									'\ncreate or replace procedure %I.%I('
									'\n\t%s tv_%I_%I.arr_%s%%type = null'
									'\n)'
									'\nlanguage plpgsql'
									'\nas $routine$'
									'\ndeclare'
									'\n	l_chunk_refresh_cmds text[];%s'
									'\nbegin'
									'\n	if %s is null then'
									'\n		select'
									'\n			array_agg('
									'\n				format('
									'\n					''call %I.%I(%s => %%L)'''
									'\n					, c.%s'
									'\n				)'
									'\n			)'
									'\n		into' 
									'\n			l_chunk_refresh_cmds'
									'\n		from ('
									'\n			select' 
									'\n				array_agg('
									'\n					c.%s order by c.%s'
									'\n				) as %s'
									'\n			from ('
									'\n				select' 
									'\n					c.%s'
									'\n					, ((row_number() over(order by c.%s) - 1) / %s) + 1 as bucket_num' 
									'\n				from ('
									'\n					%s'
									'\n				) c'
									'\n			) c'
									'\n			group by' 
									'\n				c.bucket_num'
									'\n		) c;'
									'\n'
									'\n		call ${stagingSchemaName}.p_execute_in_parallel('
									'\n			i_commands => l_chunk_refresh_cmds'
									'\n		);'
									'\n	else'
									'\n		%s'
									'\n	end if;'
									'\nend'
									'\n$routine$;'
									, i_view_rec.internal_name
									, i_view_rec.schema_name
									, i_view_rec.mv_emulation_chunking_field
									, i_view_rec.schema_name
									, i_view_rec.internal_name
									, i_view_rec.mv_emulation_chunking_field
									, i_view_rec.schema_name
									, i_view_rec.mv_emulation_table_func_name
									, i_view_rec.mv_emulation_refresh_proc_param
									, i_view_rec.internal_name
									, i_view_rec.schema_name
									, i_view_rec.mv_emulation_chunking_field
									, i_view_rec.schema_name
									, i_view_rec.internal_name
									, target_query
									, i_view_rec.schema_name
									, i_view_rec.mv_emulation_refresh_proc_name
									, i_view_rec.mv_emulation_refresh_proc_param
									, i_view_rec.internal_name
									, i_view_rec.schema_name
									, i_view_rec.mv_emulation_chunking_field
									, case 
										when i_view_rec.mv_emulation_with_partitioning then
											E'\n\tl_chunk_rec record;'
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
									, i_view_rec.mv_emulation_chunks_bucket_size
									, ${mainSchemaName}.f_indent_text(
										i_text => i_view_rec.mv_emulation_chunks_query									
										, i_indentation_level => 5
									)
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
														'\n			create table %I.%I_%%s'
														'\n				(like %I.%I including defaults including constraints)'
														'\n			;'
														'\n			alter table %I.%I_%%s add constraint chk_%%s$%s'
														'\n				check (%s in (%%L::%%s))'
														'\n			;'
														'\n			insert into %I.%I_%%s'
														'\n			select * from %I.%I(%s => %%L::%%s[])'
														'\n			;'
														'\n			alter table %I.%I attach partition %I.%I_%%s'
														'\n				for values in (%%L::%%s)'	
														'\n			;'
														'\n			alter table %I.%I_%%s drop constraint chk_%%s$%s'
														'\n			;'
														'\n			$ddl$'
														'\n			, chunk.sys_name'
														'\n			, chunk.sys_name'
														'\n			, chunk.sys_name'
														'\n			, chunk.id'
														'\n			, pg_catalog.pg_typeof(chunk.id)'
														'\n			, chunk.sys_name'
														'\n			, array[chunk.id]'
														'\n			, pg_catalog.pg_typeof(chunk.id)'
														'\n			, chunk.sys_name'
														'\n			, chunk.id'
														'\n			, pg_catalog.pg_typeof(chunk.id)'
														'\n			, chunk.sys_name'
														'\n			, chunk.sys_name'
														'\n		)'
														'\n		, E'';\\n'''
														'\n	) filter ('
														'\n		where '
														'\n			p.partition_table_name is null'
														'\n	) as new_partition_ddl_cmds'
														'\n	, array_agg('
														'\n		chunk.id'
														'\n	) filter ('
														'\n		where '
														'\n			p.partition_table_name is not null'
														'\n	) as existing_partition_chunks'
														'\n	, string_agg('
														'\n		format('''
														'\n			truncate %I.%I_%%s'
														'\n			'''
														'\n			, chunk.sys_name'
														'\n		)'
														'\n		, E'';\\n'''
														'\n	) filter ('
														'\n		where '
														'\n			p.partition_table_name is not null'
														'\n	) as existing_partition_truncate_cmds'
														'\ninto'
														'\n	l_chunk_rec'
														'\nfrom ('
														'\n	select'
														'\n		chunk.id'
														'\n		, ${mainSchemaName}.f_valid_system_name('
														'\n			i_raw_name => chunk.id::text'
														'\n		) as sys_name'
														'\n	from'
														'\n		unnest(%s) chunk(id)'
														'\n) chunk'
														'\nleft join ${mainSchemaName}.v_sys_table_partition p'
														'\n	on p.schema_name = ''%I'''
														'\n	and p.table_name = ''%I'''
														'\n	and p.partition_table_name = ''%I_''::name || chunk.sys_name' 
														'\n	and p.partition_schema_name = ''%I'''
														'\n;'
														'\n'
														'\nif l_chunk_rec.new_partition_ddl_cmds is not null then '
														'\n execute'
														'\n 	l_chunk_rec.new_partition_ddl_cmds'
														'\n ;'
														'\nend if;'
														'\n'
														'\nif l_chunk_rec.existing_partition_truncate_cmds is not null then '
														'\n execute'
														'\n 	l_chunk_rec.existing_partition_truncate_cmds'
														'\n ;'
														'\nend if;'
														'\n'
														'\nif l_chunk_rec.existing_partition_chunks is not null then '
														'\n	insert into %I.%I'
														'\n	select * from %I.%I(%s => l_chunk_rec.existing_partition_chunks)'
														'\n	;'
														'\nend if;'
														, i_view_rec.schema_name
														, i_view_rec.internal_name
														, i_view_rec.schema_name
														, i_view_rec.internal_name
														, i_view_rec.schema_name
														, i_view_rec.internal_name
														, i_view_rec.mv_emulation_chunking_field
														, i_view_rec.mv_emulation_chunking_field
														, i_view_rec.schema_name
														, i_view_rec.internal_name
														, i_view_rec.schema_name
														, i_view_rec.mv_emulation_table_func_name
														, i_view_rec.mv_emulation_refresh_proc_param
														, i_view_rec.schema_name
														, i_view_rec.internal_name
														, i_view_rec.schema_name
														, i_view_rec.internal_name
														, i_view_rec.schema_name
														, i_view_rec.internal_name
														, i_view_rec.mv_emulation_chunking_field
														, i_view_rec.schema_name
														, i_view_rec.internal_name
														, i_view_rec.mv_emulation_refresh_proc_param
														, i_view_rec.schema_name
														, i_view_rec.internal_name
														, i_view_rec.internal_name
														, i_view_rec.schema_name
														, i_view_rec.schema_name
														, i_view_rec.internal_name
														, i_view_rec.schema_name
														, i_view_rec.mv_emulation_table_func_name
														, i_view_rec.mv_emulation_refresh_proc_param
													)												
												else
													format(
														E'\n\ndelete from %I.%I where %s = any(%s);'
														'\n\ninsert into %I.%I'
														'\nselect * from %I.%I(%s => %s);'														
														, i_view_rec.schema_name
														, i_view_rec.internal_name
														, i_view_rec.mv_emulation_chunking_field
														, i_view_rec.mv_emulation_refresh_proc_param												
														, i_view_rec.schema_name
														, i_view_rec.internal_name
														, i_view_rec.schema_name
														, i_view_rec.mv_emulation_table_func_name
														, i_view_rec.mv_emulation_refresh_proc_param												
														, i_view_rec.mv_emulation_refresh_proc_param												
													)
											end																									
										, i_indentation_level => 2
									)
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
				, '\/\*\s*\#chunking_filter\:\s*.+?\s*\*\/' 
				, 'i'
			) as chunking_filter_marker
			, regexp_match(
				chunking_filter_marker[1]
				, '\/\*\s*\#chunking_filter\:\s*(.+?)\s*\*\/' 
				, 'i'
			) as chunking_filter_expr
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
			) as target_query
	) 
	loop
		execute
			l_sttmnt.ddl_sttmnt
		;
	
		if l_sttmnt.is_matview_query then 
			l_is_matview_recognized := true;
		end if;
	end loop;

	if not l_is_matview_recognized then
		raise 'The materialized view %.% is not defined as expected', i_view_rec.schema_name, i_view_rec.internal_name; 
	end if;
end
$procedure$;	

comment on procedure p_build_matview_emulation(
	${mainSchemaName}.v_meta_view
) is 'Сгенерировать эмуляцию материализованного представления';
