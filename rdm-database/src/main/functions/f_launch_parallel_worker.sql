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
	)
returns name
language plpgsql
volatile
as $function$
declare
	l_worker_num ${stagingSchemaName}.parallel_worker.worker_num%type;
	l_worker_name name;
	l_is_new_worker boolean;
	l_prev_mode_async boolean;
	l_command text;
	l_db name := current_database();
	l_user name := session_user;
	l_start_timestamp timestamp := clock_timestamp();
begin
	delete from 	
		ng_staging.parallel_worker
	where 
		context_id = i_context_id
		and operation_instance_id = i_operation_instance_id
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
			context_id = i_context_id
			and operation_instance_id = i_operation_instance_id
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
				i_context_id 
				, i_operation_instance_id
				, worker_num
				, current_timestamp			
				, i_extra_info
				, i_async_mode
			from (
				select (
						select 
							count(*)
						from 
							${stagingSchemaName}.parallel_worker
						where 
							context_id = i_context_id
							and operation_instance_id = i_operation_instance_id
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
				start_time = current_timestamp
				, extra_info = i_extra_info
				, async_mode = i_async_mode
			where 
				context_id = i_context_id
				and operation_instance_id = i_operation_instance_id
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
					i_context_id => i_context_id
					, i_operation_instance_id => i_operation_instance_id
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

	l_worker_name := 
		${stagingSchemaName}.f_parallel_worker_name(
			i_context_id => i_context_id
			, i_operation_instance_id => i_operation_instance_id
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
					'dbname=%s user=%s'
					, l_db
					, l_user
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
							when i_async_mode then 
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

	if i_async_mode then
		if ${dbms_extension.dblink.schema}.dblink_send_query(
			l_worker_name
			, l_command
		) != 1 
		then
			raise exception 
				'Error sending command to the worker: %: % (error description: %)'
				, l_worker_name
				, i_command
				, ${dbms_extension.dblink.schema}.dblink_error_message(
					l_worker_name
				)
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
	) is 'Параллельная обработка. Запустить рабочий процесс многопоточной операции'
;
