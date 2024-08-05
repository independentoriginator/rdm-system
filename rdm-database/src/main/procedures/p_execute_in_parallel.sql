drop procedure if exists ${stagingSchemaName}.p_execute_in_parallel(text[], integer, text, text, integer, integer, integer);

create or replace procedure ${stagingSchemaName}.p_execute_in_parallel(
	i_commands text[]
	, i_thread_max_count integer = ${max_parallel_worker_processes}
	, i_scheduler_type_name text = null
	, i_scheduled_task_name text = null -- 'project_internal_name.scheduled_task_internal_name'
	, i_scheduled_task_stage_ord_pos integer = 0
	, i_iteration_number integer = -1
	, i_wait_for_delay_in_seconds integer = 1
	, i_timeout_in_hours integer = 8
)
language plpgsql
as $procedure$
declare 
	l_connection text;
	l_connections text[];
	l_db name := current_database();
	l_user name := session_user;
	l_command_index integer;
	l_command_count integer;
	l_command text;
	l_last_err_msg text;
	l_msg_text text;
	l_exception_detail text;
	l_exception_hint text;
	l_result text;
	l_bool_result boolean;
	l_start_timestamp timestamp := clock_timestamp();
begin
	if i_scheduler_type_name is not null 
		and i_scheduled_task_name is not null 
		and i_thread_max_count > 1
		and i_iteration_number >= 0
		and exists (
			select 
				1
			from
				information_schema.routines r
			where 
				r.routine_schema = '${stagingSchemaName}'
				and r.routine_name = 'f_execute_in_parallel_with_' || i_scheduler_type_name
				and r.routine_type = 'FUNCTION' 
				and r.data_type = 'boolean'
		)
	then
		execute 
			format('
					select ${stagingSchemaName}.%I(
						i_scheduled_task_name => $1
						, i_scheduled_task_stage_ord_pos => $2
						, i_commands => $3
						, i_iteration_number => $4
						, i_thread_max_count => $5
					)
				'
				, 'f_execute_in_parallel_with_' || i_scheduler_type_name
			)
		into l_bool_result
		using 
			 i_scheduled_task_name
			 , i_scheduled_task_stage_ord_pos
			 , i_commands
			 , i_iteration_number
			 , i_thread_max_count
		;
		if l_bool_result then
			return;
		end if;
	end if;

	l_command_count := cardinality(i_commands);
	l_command_index := array_lower(i_commands, 1);
	
	if i_thread_max_count > 1 
		and exists (
			select 
				1
			from
				pg_catalog.pg_extension e
			where 
				e.extname = 'dblink'
		)
	then
		<<command_loop>>
		while l_command_index <= l_command_count and l_last_err_msg is null loop
			l_connections := array[]::text[];	
		
			for i in 1..least(array_length(i_commands, 1) - l_command_index + 1, i_thread_max_count) loop
				l_connection := 
					'${stagingSchemaName}.parallel'
					|| '$N' || i::text				
					|| '$' || coalesce(replace(i_scheduled_task_name, ' ', '_'), '')
					|| '$' || l_user
					;
				
				begin
					if (select coalesce(l_connection = any(${dbms_extension.dblink.schema}.dblink_get_connections()), false)) then 			
						perform ${dbms_extension.dblink.schema}.dblink_disconnect(l_connection);
					end if;
				
					perform ${dbms_extension.dblink.schema}.dblink_connect_u(l_connection, 'dbname=' || l_db || ' user=' || l_user);
		
					l_connections := array_append(l_connections, l_connection);
				exception
				when others then
					if array_length(l_connections, 1) > 0 then		
						get stacked diagnostics
							l_msg_text = MESSAGE_TEXT
							, l_exception_detail = PG_EXCEPTION_DETAIL
							, l_exception_hint = PG_EXCEPTION_HINT
							;
						raise notice 
							'dblink connection error: %: % (hint: %)'
							, l_msg_text
							, l_exception_detail
							, l_exception_hint
							;
					else 
						raise;
					end if;
				end;
			end loop;
			
			if coalesce(array_length(l_connections, 1), 0) = 0 then
				raise exception 'No dblink connections created';
			end if;
		
			<<waiting_for_completion>>
			foreach l_connection in array l_connections loop
				if ${dbms_extension.dblink.schema}.dblink_send_query(l_connection, i_commands[l_command_index]) != 1 then
					while ${dbms_extension.dblink.schema}.dblink_is_busy(l_connection) = 1 loop 
						if extract(hours from clock_timestamp() - l_start_timestamp) >= i_timeout_in_hours then
							l_last_err_msg := 'Timeout occured while waiting for commands completion';
							exit waiting_for_completion;
						end if;
						perform pg_sleep(i_wait_for_delay_in_seconds);
					end loop;
					l_last_err_msg := ${dbms_extension.dblink.schema}.dblink_error_message(l_connection);
					exit waiting_for_completion;
				end if;		
			
				l_command_index := l_command_index + 1;
			end loop;	
			
			if l_last_err_msg is not null then
				foreach l_connection in array l_connections loop
					perform ${dbms_extension.dblink.schema}.dblink_cancel_query(l_connection);
				end loop;
			end if;
		
			foreach l_connection in array l_connections loop
				select val 
				into l_result
				from ${dbms_extension.dblink.schema}.dblink_get_result(l_connection) as res(val text)
				;
			end loop;
		
			foreach l_connection in array l_connections loop
				perform ${dbms_extension.dblink.schema}.dblink_disconnect(l_connection);		
			end loop;
		end loop command_loop;
	else
		if i_commands is not null then
			foreach l_command in array i_commands loop
				execute l_command;
			end loop;
		end if;
	end if;
	
	if l_last_err_msg is not null then
		raise exception 'p_execute_in_parallel failure: %', l_last_err_msg;	
	end if;
end
$procedure$;

comment on procedure ${stagingSchemaName}.p_execute_in_parallel(
	text[]
	, integer
	, text
	, text
	, integer
	, integer
	, integer
	, integer
) is 'Исполнение набора команд в параллельном режиме';

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

create or replace procedure 
	${stagingSchemaName}.p_execute_in_parallel(
		i_command_list_query text
		, i_do_while_checking_condition text = null
		, i_context_id ${stagingSchemaName}.parallel_worker.context_id%type = 0 -- for example, system identitifier of a caller procedure 
		, i_operation_instance_id ${stagingSchemaName}.parallel_worker.operation_instance_id%type = 0 -- for example, pg_backend_pid()
		, i_use_notifications boolean = true 
		, i_max_worker_processes integer = ${max_parallel_worker_processes}
		, i_polling_interval interval = '10 seconds'
		, i_max_run_time interval = '8 hours'
		, i_close_process_pool_on_completion boolean = true
		, i_application_name name = '${project_internal_name}' 
	)
language plpgsql
as $procedure$
declare
 	l_is_multithreaded_process boolean := (
			i_max_worker_processes > 1 
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
			context_id = i_context_id
			and operation_instance_id = i_operation_instance_id
		;
	
		if i_use_notifications then
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
				)
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
		if l_is_multithreaded_process then
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
						, i_extra_info => l_extra_info
						, i_context_id => l_context_id
						, i_operation_instance_id => l_operation_instance_id
						, i_use_notifications => i_use_notifications
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
					context_id = i_context_id
					and operation_instance_id = i_operation_instance_id
					and start_time is not null		
					and async_mode = true
			) 
			then
				perform
					${stagingSchemaName}.f_wait_for_parallel_process_completion(
						i_context_id => l_context_id
						, i_operation_instance_id => l_operation_instance_id
						, i_wait_for_the_first_one_to_complete => (i_do_while_checking_condition is not null)
						, i_use_notifications => i_use_notifications
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
					${stagingSchemaName}.f_parallel_worker_name(
						i_context_id => i_context_id
						, i_operation_instance_id => i_operation_instance_id
						, i_worker_num => worker_num
					)
				from 
					${stagingSchemaName}.parallel_worker
				where 
					context_id = i_context_id
					and operation_instance_id = i_operation_instance_id
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
				context_id = i_context_id
				and operation_instance_id = i_operation_instance_id
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
				context_id = i_context_id
				and operation_instance_id = i_operation_instance_id
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
		, interval
		, interval
		, boolean
		, name
	) is 'Исполнение набора команд в параллельном режиме'
;

