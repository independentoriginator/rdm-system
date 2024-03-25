create or replace procedure p_build_matview_emulation(
	i_view_rec ${mainSchemaName}.v_meta_view
)
language plpgsql
as $procedure$
declare 
	l_sttmnt record;
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
									E'create or replace procedure %I.p_refresh_%I()'
									'\nlanguage plpgsql'
									'\nas $routine$'
									'\nbegin'
									'\n\t%s'
									'\nend'
									'\n$routine$;'
									, i_view_rec.schema_name
									, i_view_rec.internal_name
									, format(
										E'truncate %I.%I;'
										'\n\n\tinsert into %I.%I\n\t%s\n\t;'
										, i_view_rec.schema_name
										, i_view_rec.internal_name
										, i_view_rec.schema_name
										, i_view_rec.internal_name
										, view_query[1]
									)
								)
							else
								format(
									E'create or replace procedure %I.p_refresh_%I()'
									'\nlanguage plpgsql'
									'\nas $routine$'
									'\ndeclare'
									'\n\tl_query text := $sql$'
									'\n\t%s'
									'\n\t$sql$'
									'\n\t;'
									'\n\tl_chunk_refresh_cmds text[];'
									'\nbegin'
									'\n	select'
									'\n		array_agg('
									'\n			format('
									'\n				l_query'
									'\n				, t.%s'
									'\n				, t.%s'
									'\n			)'
									'\n		)'
									'\n	into' 
									'\n		l_chunk_refresh_cmds'
									'\n	from (\n%s\n\t) t'
									'\n	;'
									'\n'
									'\n	call ${stagingSchemaName}.p_execute_in_parallel('
									'\n		i_commands => l_chunk_refresh_cmds'
									'\n	);'
									'\nend'
									'\n$routine$;'
									, i_view_rec.schema_name
									, i_view_rec.internal_name
									, format(
										E'delete from %I.%I where %s = %%L;'
										'\n\n\tinsert into %I.%I\n\t%s\n\t;'
										, i_view_rec.schema_name
										, i_view_rec.internal_name
										, i_view_rec.mv_emulation_chunking_field
										, i_view_rec.schema_name
										, i_view_rec.internal_name
										, case
											when chunking_filter_marker[1] is null then
												format(
													E'select *'
													'\n\tfrom ('
													'\n\t%s'
													'\n\t) t'
													'\n\twhere'
													'\n\t\t%s = %%L'
													, view_query[1]
													, i_view_rec.mv_emulation_chunking_field
												)													
											else
												replace(
													view_query[1]
												 	, chunking_filter_marker[1]
												 	, chunking_filter_expr[1]
												)
										end
									)
									, i_view_rec.mv_emulation_chunking_field
									, i_view_rec.mv_emulation_chunking_field
									, format(
										E'\t\twith chunks as ('
										'\n\t\t\t%s'
										'\n\t\t)'
										'\n\t\tselect'
										'\n\t\t\t%s'
										'\n\t\tfrom'
										'\n\t\t\tchunks'
										'\n\t\tunion all'
										'\n\t\t('
											'\n\t\t\tselect'
											'\n\t\t\t\t%s'
											'\n\t\t\tfrom'
											'\n\t\t\t\tchunks'
											'\n\t\t\texcept'
											'\n\t\t\t('
												'\n\t\t\t\tselect distinct'
												'\n\t\t\t\t\t%s'
												'\n\t\t\t\tfrom'
												'\n\t\t\t\t\t%I.%I'
											'\n\t\t\t)'
										'\n\t\t)'
										, replace(
											i_view_rec.mv_emulation_chunks_query
											, E'\n'
											, E'\n\t\t'
										)
										, i_view_rec.mv_emulation_chunking_field
										, i_view_rec.mv_emulation_chunking_field
										, i_view_rec.mv_emulation_chunking_field
										, i_view_rec.schema_name
										, i_view_rec.internal_name
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
	end loop;
end
$procedure$;	

comment on procedure p_build_matview_emulation(
	${mainSchemaName}.v_meta_view
) is 'Сгенерировать эмуляцию материализованного представления';
