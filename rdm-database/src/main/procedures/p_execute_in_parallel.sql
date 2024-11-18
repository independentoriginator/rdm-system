drop procedure if exists 
	${stagingSchemaName}.p_execute_in_parallel(
		text[], integer, text, text, integer, integer, integer
	)
;

drop procedure if exists 
	${stagingSchemaName}.p_execute_in_parallel(
		text[]
		, integer
		, text
		, text
		, integer
		, integer
		, integer
		, integer
	)
;

drop procedure if exists 
	${stagingSchemaName}.p_execute_in_parallel(
		text
		, text
		, ${stagingSchemaName}.parallel_worker.context_id%type 
		, ${stagingSchemaName}.parallel_worker.operation_instance_id%type 
		, integer
		, interval
		, interval
	)
;

drop procedure if exists 
	${stagingSchemaName}.p_execute_in_parallel(
		text
		, text
		, ${stagingSchemaName}.parallel_worker.context_id%type 
		, ${stagingSchemaName}.parallel_worker.operation_instance_id%type 
		, integer
		, interval
		, interval
		, boolean
	)
;

drop procedure if exists 
	${stagingSchemaName}.p_execute_in_parallel(
		text
		, text
		, ${stagingSchemaName}.parallel_worker.context_id%type 
		, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
		, boolean
		, integer
		, interval
		, interval
		, boolean
	)
;

drop procedure if exists 
	${stagingSchemaName}.p_execute_in_parallel(
		text
		, text
		, ${stagingSchemaName}.parallel_worker.context_id%type 
		, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
		, boolean
		, integer
		, interval
		, interval
		, boolean
		, name
	)
;

create or replace procedure 
	${stagingSchemaName}.p_execute_in_parallel(
		i_command_list_query text
		, i_do_while_checking_condition text = null
		, i_context_id ${stagingSchemaName}.parallel_worker.context_id%type = 0 -- for example, system identitifier of a caller procedure 
		, i_operation_instance_id ${stagingSchemaName}.parallel_worker.operation_instance_id%type = 0 -- for example, pg_backend_pid()
		, i_use_notifications boolean = true 
		, i_max_worker_processes integer = ${max_parallel_worker_processes}
		, i_single_transaction boolean = false
		, i_polling_interval interval = '10 seconds'
		, i_max_run_time interval = '8 hours'
		, i_close_process_pool_on_completion boolean = true
		, i_application_name name = '${project_internal_name}' 
	)
language plpgsql
as $procedure$
declare
 	l_is_multithreaded_process boolean := (
			(
				i_max_worker_processes > 1
				or (
					i_max_worker_processes = 1
					and i_single_transaction = false
				)
			)
			and exists (
				select 
					1
				from
					pg_catalog.pg_extension e
				where 
					e.extname = 'dblink'
			)
		)
	;
	l_use_notifications boolean := (
			i_use_notifications
			and i_max_worker_processes > 1
		)
	;
	l_async_mode boolean := (
			l_is_multithreaded_process
			and i_single_transaction = false
		)
	;
	l_context_id ${stagingSchemaName}.parallel_worker.context_id%type = coalesce(i_context_id, 0); 
	l_operation_instance_id ${stagingSchemaName}.parallel_worker.operation_instance_id%type = coalesce(i_operation_instance_id, 0); 
	l_exit_flag boolean;
	l_command text;
	l_extra_info ${stagingSchemaName}.parallel_worker.extra_info%type;
	l_notification_channel name := 
		${mainSchemaName}.f_valid_system_name(
			i_raw_name => 
				format(
					'${project_internal_name}.parallel_worker_notifications_%s_%s'
					, i_context_id
					, i_operation_instance_id
				)					
		)
	;
	l_notification_listener_worker name;
	l_worker name;
begin
	-- Make sure of start possibility
	perform 
		pg_catalog.pg_advisory_xact_lock(
			l_context_id::integer
			, l_operation_instance_id::integer
		)
	;

	if l_is_multithreaded_process then
		update
			${stagingSchemaName}.parallel_worker
		set
			start_time = null
			, extra_info = null
		where 
			context_id = l_context_id
			and operation_instance_id = l_operation_instance_id
		;
	
		if l_use_notifications then
			-- Start listening to parallel worker notifications
			l_notification_listener_worker :=  
				${stagingSchemaName}.f_launch_parallel_worker(
					i_command => 
						format(
							'listen %s'
							, l_notification_channel
						)
					, i_async_mode => false
					, i_extra_info => null
					, i_context_id => l_context_id
					, i_operation_instance_id => l_operation_instance_id
					, i_use_notifications => false
					, i_notification_channel => l_notification_channel
					, i_max_worker_processes => i_max_worker_processes
					, i_polling_interval => i_polling_interval
					, i_max_run_time => i_max_run_time
					, i_application_name => i_application_name
				)::name
			;
		
			raise notice 
				'Notification listener process started: %'
				, l_notification_listener_worker 
			;
		end if
		;
	else	
		raise notice 
			'Singlethreaded process will be executed'
			' (for multithreaded execution, install the dblink extension and set the i_max_worker_processes procedure parameter to an appropriate value)'
		;
	end if
	;
	
	<<main>>
	loop
		if l_is_multithreaded_process
			and i_single_transaction = false
		then
			-- Launch workers and wait for them to complete
			<<commands>>
			for l_command, l_extra_info in 
				execute 
					i_command_list_query 
				using 
					l_context_id
					, l_operation_instance_id  
			loop
				perform 
					${stagingSchemaName}.f_launch_parallel_worker(
						i_command => l_command
						, i_async_mode => l_async_mode
						, i_extra_info => l_extra_info
						, i_context_id => l_context_id
						, i_operation_instance_id => l_operation_instance_id
						, i_use_notifications => l_use_notifications
						, i_notification_channel => l_notification_channel
						, i_notification_listener_worker => l_notification_listener_worker
						, i_max_worker_processes => i_max_worker_processes
						, i_polling_interval => i_polling_interval
						, i_max_run_time => i_max_run_time
						, i_application_name => i_application_name
					)
				;
			end loop commands
			;
			
			-- When at least one asynchronous worker has been started, run the waiting cycle
			if exists (
				select 
					1
				from 
					${stagingSchemaName}.parallel_worker
				where 
					context_id = l_context_id
					and operation_instance_id = l_operation_instance_id
					and start_time is not null		
					and async_mode = true
			) 
			then
				perform
					${stagingSchemaName}.f_wait_for_parallel_process_completion(
						i_context_id => l_context_id
						, i_operation_instance_id => l_operation_instance_id
						, i_wait_for_the_first_one_to_complete => (i_do_while_checking_condition is not null)
						, i_use_notifications => l_use_notifications
						, i_notification_channel => l_notification_channel
						, i_notification_listener_worker => l_notification_listener_worker
						, i_polling_interval => i_polling_interval
						, i_max_run_time => i_max_run_time
					)
				;
			end if
			;
		else 
			<<commands>>
			for l_command, l_extra_info in 
				execute 
					i_command_list_query 
				using 
					l_context_id
					, l_operation_instance_id
			loop
				execute 
					l_command
				;
			end loop commands
			;
		end if
		;		
	
		if i_do_while_checking_condition is null then
			exit main
			;
		else
			execute 
				i_do_while_checking_condition 
			into 
				l_exit_flag
			;
		
			exit main 
				when l_exit_flag
			;
		end if
		;
	end loop main
	;

	if l_is_multithreaded_process then
		if i_close_process_pool_on_completion then 
			for l_worker in (
				select 
					pw.worker_name
				from (
					select 
						${stagingSchemaName}.f_parallel_worker_name(
							i_context_id => l_context_id
							, i_operation_instance_id => l_operation_instance_id
							, i_worker_num => worker_num
						) as worker_name
					from 
						${stagingSchemaName}.parallel_worker
					where 
						context_id = l_context_id
						and operation_instance_id = l_operation_instance_id
				) pw
				join unnest(${dbms_extension.dblink.schema}.dblink_get_connections()) conn(name)
					on conn.name = pw.worker_name
			)
			loop
				perform
				from
					${dbms_extension.dblink.schema}.dblink_disconnect(
						l_worker
					)
				;
			end loop
			;

			delete from 
				${stagingSchemaName}.parallel_worker
			where 
				context_id = l_context_id
				and operation_instance_id = l_operation_instance_id
			;
		else 
			perform 
				${dbms_extension.dblink.schema}.dblink_exec(
					l_notification_listener_worker
					, format(
						'unlisten %s'
						, l_notification_channel
					)
				)
			;
		
			update
				${stagingSchemaName}.parallel_worker
			set
				start_time = null
				, extra_info = null
			where 
				context_id = l_context_id
				and operation_instance_id = l_operation_instance_id
			;
		end if
		;
	end if
	;
end
$procedure$
;

comment on procedure 
	${stagingSchemaName}.p_execute_in_parallel(
		text
		, text
		, ${stagingSchemaName}.parallel_worker.context_id%type 
		, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
		, boolean
		, integer
		, boolean
		, interval
		, interval
		, boolean
		, name
	) 
	is 'Исполнение набора команд в параллельном режиме'
;

