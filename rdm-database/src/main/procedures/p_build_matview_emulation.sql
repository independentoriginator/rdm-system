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
						, format('
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
												E'truncate %I.%I;'
												'\n\ninsert into %I.%I\n%s\n;'
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
									'\ncreate or replace procedure %I.%I('
									'\n\t%s tv_%I_%I.arr_%s%%type = null'
									'\n)'
									'\nlanguage plpgsql'
									'\nas $routine$'
									'\ndeclare'
									'\n	l_chunk_refresh_cmds text[];'
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
									'\n					%s order by %s'
									'\n				) as %s'
									'\n			from ('
									'\n				select' 
									'\n					%s'
									'\n					, ntile(%s) over(order by %s) as bucket_num'
									'\n				from ('
									'\n					%s'
									'\n				) c'
									'\n			) c'
									'\n			group by' 
									'\n				bucket_num'
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
									, i_view_rec.mv_emulation_refresh_proc_name
									, i_view_rec.mv_emulation_refresh_proc_param
									, i_view_rec.internal_name
									, i_view_rec.schema_name
									, i_view_rec.mv_emulation_chunking_field
									, i_view_rec.mv_emulation_refresh_proc_param
									, i_view_rec.schema_name
									, i_view_rec.mv_emulation_refresh_proc_name
									, i_view_rec.mv_emulation_refresh_proc_param
									, i_view_rec.mv_emulation_chunking_field
									, i_view_rec.mv_emulation_chunking_field
									, i_view_rec.mv_emulation_chunking_field
									, i_view_rec.mv_emulation_chunking_field
									, i_view_rec.mv_emulation_chunking_field
									, ${max_parallel_worker_processes}
									, i_view_rec.mv_emulation_chunking_field
									, ${mainSchemaName}.f_indent_text(
										i_text => i_view_rec.mv_emulation_chunks_query									
										, i_indentation_level => 5
									)
									, ${mainSchemaName}.f_indent_text(
										i_text =>
											format(
												E'delete from %I.%I where %s = any(%s);'
												'\n\ninsert into %I.%I\n%s\n;'
												, i_view_rec.schema_name
												, i_view_rec.internal_name
												, i_view_rec.mv_emulation_chunking_field
												, i_view_rec.mv_emulation_refresh_proc_param												
												, i_view_rec.schema_name
												, i_view_rec.internal_name
												, case
													when chunking_filter_marker[1] is null then
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
													else
														replace(
															view_query[1]
														 	, chunking_filter_marker[1]
														 	, chunking_filter_expr[1]
														)
												end
											)
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
		raise 'Materialized view %.% is not defined as expected', i_view_rec.schema_name, i_view_rec.internal_name; 
	end if;
end
$procedure$;	

comment on procedure p_build_matview_emulation(
	${mainSchemaName}.v_meta_view
) is 'Сгенерировать эмуляцию материализованного представления';
