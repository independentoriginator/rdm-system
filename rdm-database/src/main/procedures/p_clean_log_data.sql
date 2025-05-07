create or replace procedure 
	${stagingSchemaName}.p_clean_log_data(
		i_data_expiration_age interval = '${log_data_expiration_age}'::interval
		, i_max_worker_processes integer = ${max_parallel_worker_processes}
		, i_polling_interval interval = '10 seconds'
		, i_max_run_time interval = '8 hours'
	)
language plpgsql
as $procedure$
begin
	-- truncate corrupted unlogged log tables if any
	call 
		${stagingSchemaName}.p_execute_in_parallel(
			i_command_list_query => 
				$sql$
				select
					format(
						'call ${stagingSchemaName}.p_truncate_corrupted_unlogged_tables(i_schema_name => %%L)'
						, t.schema_name
					)
				from (
					select distinct 
						t.schema_name
					from
						${mainSchemaName}.v_meta_type t
					where 
						t.is_logged
				) t
				$sql$
			, i_context_id => '${stagingSchemaName}.p_clean_log_data'::regproc
			, i_use_notifications => false
			, i_max_worker_processes => i_max_worker_processes
			, i_polling_interval => i_polling_interval
			, i_max_run_time => i_max_run_time
		)
	;

	-- perform a log data clean with the specified data expiration age
	call 
		${stagingSchemaName}.p_execute_in_parallel(
			i_command_list_query => 
				$sql$
				select
					format(
						'delete from %%I.%%I where age(current_date, change_date) > %%L::interval'
						, t.schema_name
						, t.log_table_name
						, i_data_expiration_age
					)
				from
					${mainSchemaName}.v_meta_type t
				where 
					t.is_logged
				$sql$
			, i_context_id => '${stagingSchemaName}.p_clean_log_data'::regproc
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
	${stagingSchemaName}.p_clean_log_data(
		interval
		, integer
		, interval
		, interval
	) 
	is 'Очистка журналов изменения данных'
;
