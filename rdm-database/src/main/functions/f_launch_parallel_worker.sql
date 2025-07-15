drop function if exists 
	${stagingSchemaName}.f_launch_parallel_worker(
		text
		, ${stagingSchemaName}.parallel_worker.context_id%type
		, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
		, name
		, integer
		, interval
		, interval
	)
;

drop function if exists 
	${stagingSchemaName}.f_launch_parallel_worker(
		text
		, ${stagingSchemaName}.parallel_worker.extra_info%type
		, ${stagingSchemaName}.parallel_worker.context_id%type
		, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
		, name
		, integer
		, interval
		, interval
		, name
		, boolean
		, boolean
	)
;

drop function if exists 
	${stagingSchemaName}.f_launch_parallel_worker(
		text
		, boolean
		, ${stagingSchemaName}.parallel_worker.extra_info%type
		, ${stagingSchemaName}.parallel_worker.context_id%type
		, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
		, boolean
		, name
		, name
		, integer
		, interval
		, interval
	)
;

drop function if exists 
	${stagingSchemaName}.f_launch_parallel_worker(
		text
		, boolean
		, ${stagingSchemaName}.parallel_worker.extra_info%type
		, ${stagingSchemaName}.parallel_worker.context_id%type
		, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
		, boolean
		, name
		, name
		, integer
		, interval
		, interval
		, name
	)
;

drop function if exists 
	${stagingSchemaName}.f_launch_parallel_worker(
		text
		, boolean
		, ${stagingSchemaName}.parallel_worker.extra_info%type
		, ${stagingSchemaName}.parallel_worker.context_id%type
		, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
		, boolean
		, name
		, name
		, integer
		, interval
		, interval
		, name
		, boolean
	)
;

create or replace function 
	${stagingSchemaName}.f_launch_parallel_worker(
		i_command text
		, i_async_mode boolean = true
		, i_extra_info ${stagingSchemaName}.parallel_worker.extra_info%type = null
		, i_context_id ${stagingSchemaName}.parallel_worker.context_id%type = 0
		, i_operation_instance_id ${stagingSchemaName}.parallel_worker.operation_instance_id%type = 0
		, i_use_notifications boolean = true
		, i_notification_channel name = null
		, i_notification_listener_worker name = null
		, i_max_worker_processes integer = ${max_parallel_worker_processes}
		, i_polling_interval interval = '10 seconds'
		, i_max_run_time interval = '8 hours'
		, i_application_name name = '${project_internal_name}'
		, i_is_oneoff boolean = false
		, i_retry_attempt_number integer = 0		
	)
returns text
language plpgsql
volatile
as $function$
declare
	l_context_id ${stagingSchemaName}.parallel_worker.context_id%type := coalesce(i_context_id, 0);
	l_operation_instance_id ${stagingSchemaName}.parallel_worker.operation_instance_id%type := coalesce(i_operation_instance_id, 0);
	l_async_mode boolean := coalesce(i_async_mode, true);
	l_worker_num ${stagingSchemaName}.parallel_worker.worker_num%type;
	l_worker_name name;
	l_result_value text;
	l_is_new_worker boolean;
	l_prev_mode_async boolean;
	l_command text;
	l_db name := current_database();
	l_user name := session_user;
	l_start_timestamp timestamp := clock_timestamp();
	l_message text;
begin
	-- Make sure of start possibility
	perform 
		pg_catalog.pg_advisory_xact_lock(
			l_context_id::integer
			, l_operation_instance_id::integer
		)
	;
	
	if i_is_oneoff then
		if l_async_mode then 
			raise exception 
				'One-off command must be executed in synchronous mode'
			;
		end if
		;
		l_worker_num := 0;
	else
		delete from 	
			ng_staging.parallel_worker
		where 
			context_id = l_context_id
			and operation_instance_id = l_operation_instance_id
			and worker_num > i_max_worker_processes
			and (
				start_time is null
				or clock_timestamp() - start_time >= i_max_run_time
			)
		;		
		
		<<waiting_for_available_worker>>
		loop
			l_is_new_worker := true;
	
			-- Get available worker if any
			select 
				worker_num
				, async_mode
			into 
				l_worker_num
				, l_prev_mode_async
			from 
				${stagingSchemaName}.parallel_worker
			where 
				context_id = l_context_id
				and operation_instance_id = l_operation_instance_id
				and (
					start_time is null
					or clock_timestamp() - start_time >= i_max_run_time
				)
			order by 
				worker_num
				, start_time
			limit 1
			for update skip locked
			;
			
			if l_worker_num is null then
				-- Create new worker within the total worker count limit
				insert into 
					${stagingSchemaName}.parallel_worker(
						context_id
						, operation_instance_id
						, worker_num
						, start_time
						, extra_info
						, async_mode
					)
				select
					l_context_id 
					, l_operation_instance_id
					, worker_num
					, ${mainSchemaName}.f_current_timestamp()			
					, i_extra_info
					, l_async_mode
				from (
					select (
							select 
								count(*)
							from 
								${stagingSchemaName}.parallel_worker
							where 
								context_id = l_context_id
								and operation_instance_id = l_operation_instance_id
						) + 1 
						as worker_num
				) w 
				where 
					worker_num <= i_max_worker_processes 
				returning 
					worker_num		
				into 
					l_worker_num
				;
			else
				l_is_new_worker := false
				;
			
				update 
					${stagingSchemaName}.parallel_worker
				set 
					start_time = ${mainSchemaName}.f_current_timestamp()
					, extra_info = i_extra_info
					, async_mode = l_async_mode
				where 
					context_id = l_context_id
					and operation_instance_id = l_operation_instance_id
					and worker_num = l_worker_num
				;
			end if;
		
			if l_worker_num is not null 
			then 
				exit waiting_for_available_worker
				;
			else	
				if (
						i_notification_listener_worker is null
						and i_use_notifications
					)
					or not ${stagingSchemaName}.f_wait_for_parallel_process_completion(
						i_context_id => l_context_id
						, i_operation_instance_id => l_operation_instance_id
						, i_wait_for_the_first_one_to_complete => true
						, i_use_notifications => i_use_notifications 
						, i_notification_channel => i_notification_channel
						, i_notification_listener_worker => i_notification_listener_worker
						, i_polling_interval => i_polling_interval
						, i_max_run_time => i_max_run_time
					)
				then 
					raise exception 
						'No parallel workers available'
					;		
				end if
				;
			end if
			;
		
		end loop waiting_for_available_worker
		;
	end if
	;

	l_worker_name := 
		${stagingSchemaName}.f_parallel_worker_name(
			i_context_id => l_context_id
			, i_operation_instance_id => l_operation_instance_id
			, i_worker_num => l_worker_num
		)
	;
	
	if (
		select 
			coalesce(
				l_worker_name = 
					any(
						${dbms_extension.dblink.schema}.dblink_get_connections()
					)
				, false
			)
	) 
	then
		if coalesce(l_prev_mode_async, true) then
			while 
				${dbms_extension.dblink.schema}.dblink_is_busy(
					l_worker_name
				) = 1 
			loop
				call 
					${mainSchemaName}.p_delay_execution(
						i_delay_interval => i_polling_interval
						, i_max_run_time => i_max_run_time
						, i_start_timestamp => l_start_timestamp
					)
				;	
			end loop
			;		
	
			-- Request the result of the previous async query twice to use the existing connection again 
			for i in 1..2 loop
				perform
				from
					${dbms_extension.dblink.schema}.dblink_get_result(
						l_worker_name
					) as res(val text)
				;
			end loop
			;
		end if
		;
	else
		perform 
			${dbms_extension.dblink.schema}.dblink_connect_u(
				l_worker_name
				, format(
					'dbname=%s user=%s application_name=%s'
					, l_db
					, l_user
					, i_application_name
				)
			)
		;
	end if
	;

	l_command := 
		case 
			when i_use_notifications then
				concat_ws(
					E';\n'
					, i_command
					, format(
						case 
							when l_async_mode then 
								'select pg_catalog.pg_notify(%L, %L)'
							else 
								'do $$ begin perform pg_catalog.pg_notify(%L, %L); end $$'
						end
						, i_notification_channel
						, l_worker_num
					)
				)
			else 
				i_command
		end
	;

	if i_is_oneoff then
		select
			res.val
		into
			l_result_value
		from
			${dbms_extension.dblink.schema}.dblink(
				l_worker_name
				, l_command
			)
			as res(val text)
		;
		
		perform
			from
				${dbms_extension.dblink.schema}.dblink_disconnect(
					l_worker_name
				)
			;
		
		return 
			l_result_value
		;
	else
		if l_async_mode then
			if ${dbms_extension.dblink.schema}.dblink_send_query(
				l_worker_name
				, l_command
			) != 1 
			then
				l_message = 
					${dbms_extension.dblink.schema}.dblink_error_message(
						l_worker_name
					)
				;
				if l_message = 'another command is already in progress'
					and i_retry_attempt_number <= 3 
				then 
					call 
						${mainSchemaName}.p_delay_execution(
							i_delay_interval => i_polling_interval
							, i_max_run_time => i_max_run_time
							, i_start_timestamp => l_start_timestamp
						)
					;	
	
					return
						${stagingSchemaName}.f_launch_parallel_worker(
							i_command => i_command
							, i_async_mode => i_async_mode
							, i_extra_info => i_extra_info
							, i_context_id => i_context_id
							, i_operation_instance_id => i_operation_instance_id
							, i_use_notifications => i_use_notifications
							, i_notification_channel => i_notification_channel
							, i_notification_listener_worker => i_notification_listener_worker
							, i_max_worker_processes => i_max_worker_processes
							, i_polling_interval => i_polling_interval
							, i_max_run_time => i_max_run_time
							, i_application_name => i_application_name
							, i_is_oneoff => i_is_oneoff
							, i_retry_attempt_number => i_retry_attempt_number + 1		
						)
					;
				else 
					raise exception 
						'Error sending command to the worker: %: % (error description: %)'
						, l_worker_name
						, i_command
						, l_message
					;
				end if
				;
			end if
			;
		else
			perform 
				${dbms_extension.dblink.schema}.dblink_exec(
					l_worker_name
					, l_command
				)
			;
		end if
		;
	end if
	;	

	return
		l_worker_name
	;
end
$function$;	

comment on function 
	${stagingSchemaName}.f_launch_parallel_worker(
		text
		, boolean
		, ${stagingSchemaName}.parallel_worker.extra_info%type
		, ${stagingSchemaName}.parallel_worker.context_id%type
		, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
		, boolean
		, name
		, name
		, integer
		, interval
		, interval
		, name
		, boolean
		, integer
	) 
	is 'Параллельная обработка. Запустить рабочий процесс многопоточной операции'
;
