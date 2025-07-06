create or replace procedure p_refresh_materialized_view(
	i_view_id ${mainSchemaName}.meta_view.id%type
)
language plpgsql
security definer
as $procedure$
declare 
	l_command text;
begin
	select
		format(
			E'do $$'
			'\ndeclare'
			'\n	l_start_timestamp timestamp := clock_timestamp();'
			'\nbegin'
			'\n	perform'
			'\n	from'
			'\n		${mainSchemaName}.meta_view'
			'\n	where'
			'\n		id = %s'
			'\n	for share'
			'\n	;'
			'\n	%s'
			'\n	;'
			'\n	update'
			'\n		${mainSchemaName}.meta_view'
			'\n	set'
			'\n		is_valid = true'
			'\n		, refresh_time = ${mainSchemaName}.f_current_timestamp()'
			'\n	where'
			'\n		id = %s'
			'\n	;'
			'\n	insert into'
			'\n		${stagingSchemaName}.materialized_view_refresh_duration('
			'\n			meta_view_id'
			'\n			, start_time'
			'\n			, end_time'
			'\n		)'
			'\n	values('
			'\n		%s'
			'\n		, l_start_timestamp'
			'\n		, clock_timestamp()'
			'\n	)'
			'\n	;'
			'\nend $$'
			, t.id
			, case 
				when t.is_matview_emulation then
					${mainSchemaName}.f_indent_text(
						i_text =>  
							concat_ws(
								E'\n;\n'
								, format(
									E'insert into'
									'\n	${stagingSchemaName}.matview_stat_inquiry_log('
									'\n		stat_inquiring_view_id'
									'\n		, stat_inquiry_time'
									'\n		, stat_update_time'
									'\n		, stat_autoupdate_time'
									'\n		, meta_type_id'
									'\n		, meta_view_id'
									'\n	)'
									'\nselect'
									'\n	dep.view_id as stat_inquiring_view_id'
									'\n	, ${mainSchemaName}.f_current_timestamp() as stat_inquiry_time'
									'\n	, stat.last_analyze as stat_update_time'
									'\n	, stat.last_autoanalyze as stat_autoupdate_time'
									'\n	, dep.master_type_id as meta_type_id'
									'\n	, dep.master_view_id as meta_view_id'
									'\nfrom' 
									'\n	${mainSchemaName}.meta_view_dependency dep' 
									'\nleft join ${mainSchemaName}.v_meta_type master_type'
									'\n	on master_type.id = dep.master_type_id'
									'\nleft join ${mainSchemaName}.v_meta_view master_view'
									'\n	on master_view.id = dep.master_view_id'
									'\n	and master_view.is_materialized'
									'\njoin lateral ('
									'\n	values'
									'\n		('
									'\n			master_view.schema_name'
									'\n			, master_view.internal_name'
									'\n		)'
									'\n		, ('
									'\n			master_type.schema_name'
									'\n			, master_type.internal_name'
									'\n		)'
									'\n		, ('
									'\n			master_type.schema_name'
									'\n			, case'
									'\n				when master_type.is_localization_table_generated then'
									'\n					master_type.localization_table_name'
									'\n			end'
									'\n		)'
									'\n) as master_table('
									'\n	schema_name'
									'\n	, table_name'
									'\n)'
									'\n	on master_table.table_name is not null'
									'\nleft join pg_catalog.pg_stat_all_tables stat'
									'\n	on stat.schemaname = master_table.schema_name'
									'\n	and stat.relname = master_table.table_name'
									'\nwhere'
									'\n	dep.view_id = %s'
									'\n	and dep.level <= 2'
									, i_view_id
								)
								, case
									when t.actualize_inquiring_statictics then 
										format(
											E'\n-- enforce actualization of the statistics that will be inquired by the materialized view'
											'\nexecute'
											'\n	coalesce(('
											'\n			select' 
											'\n				''analyze '''
											'\n				|| string_agg('
											'\n					format('
											'\n						''%%I.%%I'''
											'\n						, t.schema_name'
											'\n						, t.table_name'
											'\n					)'
											'\n					, '', '''
											'\n					order by'
											'\n						t.schema_name'
											'\n						, t.table_name'									
											'\n				)'
											'\n			from ('
											'\n				select'
											'\n					master_table.schema_name'
											'\n					, master_table.table_name'
											'\n				from'
											'\n					${mainSchemaName}.meta_view_chunk_dependency dep'
											'\n				left join ${mainSchemaName}.v_meta_view master_view'
											'\n					on master_view.id = dep.master_view_id'
											'\n					and master_view.is_matview_emulation = false' -- emulated matviews are expected to always have up-to-date statistics
											'\n				left join ${mainSchemaName}.v_meta_type master_type'
											'\n					on master_type.id = dep.master_type_id'
											'\n				join lateral ('
											'\n					values'
											'\n						('
											'\n							master_view.schema_name'
											'\n							, master_view.internal_name'
											'\n						)'
											'\n						, ('
											'\n							master_type.schema_name'
											'\n							, master_type.internal_name'
											'\n						)'
											'\n						, ('
											'\n							master_type.schema_name'
											'\n							, case'
											'\n								when master_type.is_localization_table_generated then'
											'\n									master_type.localization_table_name'
											'\n							end'
											'\n						)'
											'\n				) as master_table('
											'\n					schema_name'
											'\n					, table_name'
											'\n				)'
											'\n					on master_table.table_name is not null'
											'\n				where'
											'\n					dep.view_id = %s'
											'\n			) t'
											'\n			join pg_catalog.pg_stat_all_tables s'
											'\n				on s.schemaname = t.schema_name'
											'\n				and s.relname = t.table_name'
											'\n			where'
											'\n				coalesce('
											'\n					current_timestamp - greatest(s.last_analyze, s.last_autoanalyze)'
											'\n					, ''${statictics_out_of_date_threshold}''::interval'
											'\n				) >= ''${statictics_out_of_date_threshold}''::interval'
											'\n		)'									
											'\n		, '''''
											'\n	)'										
											, t.id
										)			
								end
								, format(
									'call %I.p_refresh_%I()'
									, t.schema_name
									, t.internal_name
								)
								, format(
									'analyze %I.%I'
									, t.schema_name
									, t.internal_name
								)
								, formmat(
									E'insert into'
									'\n	${stagingSchemaName}.matview_stat_explicit_update_log('
									'\n		meta_view_id'
									'\n		, update_time'
									'\n		, session_context'
									'\n	)'
									'\nvalues('
									'\n	%s'
									'\n	, ${mainSchemaName}.f_current_timestamp()'
									'\n	, ${stagingSchemaName}.f_session_context('
									'\n		i_key => ''${session_context_key_task_name}'''
									'\n	)'
									'\n)'
									, i_view_id
								)
							)
						, i_indentation_level => 1
					)
				else
					${mainSchemaName}.f_materialized_view_refresh_command(
						i_schema_name => t.schema_name
						, i_internal_name => t.internal_name
						, i_has_unique_index => t.has_unique_index
						, i_is_populated => t.is_populated
					)
			end
			, t.id
			, t.id
		)
	into 
		l_command
	from 
		${mainSchemaName}.v_meta_view t
	where 
		t.id = i_view_id
	;

	execute 
		l_command
	;	
end
$procedure$;		

-- Execute persmission for the ETL user role
do $$
begin
	if length('${etlUserRole}') > 0
		and not exists (
			select 
				1
			from 
				information_schema.role_routine_grants g
	  		where
	  			g.grantee = '${etlUserRole}'
	  			and g.routine_schema = '${mainSchemaName}'
	  			and g.routine_name = 'p_refresh_materialized_view'
	  			and g.privilege_type = 'EXECUTE'
		)
	then
		execute format('grant execute on procedure p_refresh_materialized_view to %s', '${etlUserRole}');
	end if;
end 
$$;

comment on procedure p_refresh_materialized_view(
	${mainSchemaName}.meta_view.id%type
) is 'Обновить материализованное представление';
