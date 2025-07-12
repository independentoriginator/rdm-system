create or replace procedure 
	p_sys_update_table_statistics(
		i_schema_name name[] = null
		, i_check_out_of_date_threshold boolean = true
		, i_max_worker_processes integer = ${max_parallel_worker_processes}
		, i_polling_interval interval = '10 seconds'
		, i_max_run_time interval = '8 hours'
	)
language plpgsql
as $procedure$
declare 
	l_schema_name name[] := i_schema_name;
begin
	if l_schema_name is null or cardinality(l_schema_name) = 0 then
		select 
			array_agg(internal_name)
		into
			l_schema_name	
		from 
			ng_rdm.meta_schema
		where
			not is_external 
			and not is_disabled			
		;
	end if
	;

	call 
		${stagingSchemaName}.p_execute_in_parallel(
			i_command_list_query => 
				format(
					$sql$
					select
						format(
							'analyze %%I.%%I'
							, t.obj_schema
							, t.obj_name
						)
					from 
						${mainSchemaName}.v_sys_obj t
					left join pg_catalog.pg_stat_all_tables s
						on s.schemaname = t.obj_schema
						and s.relname = t.obj_name
					where 
						t.obj_schema = any(string_to_array(%L, ','))
						and t.obj_specific_type = 'table'%s
					$sql$
					, array_to_string(l_schema_name, ',')
					, case 
						when coalesce(i_check_out_of_date_threshold, true) then
							${mainSchemaName}.f_indent_text(
								i_text => 
									E'\nand coalesce('
									'\n	current_timestamp - greatest(s.last_analyze, s.last_autoanalyze)'
									'\n	, ''${statictics_out_of_date_threshold}''::interval'
									'\n) >= ''${statictics_out_of_date_threshold}''::interval'
								, i_indentation_level => 1
							)
						else 
							''
					end
				)
			, i_context_id => '${mainSchemaName}.p_sys_update_table_statistics'::regproc
			, i_use_notifications => false
			, i_max_worker_processes => i_max_worker_processes
			, i_polling_interval => i_polling_interval
			, i_max_run_time => i_max_run_time
			, i_close_process_pool_on_completion => true
		)
	;
end
$procedure$
;

comment on procedure 
	p_sys_update_table_statistics(
		name[]
		, boolean
		, integer
		, interval
		, interval
	) 
	is 'Обновление статистики для таблиц'
;