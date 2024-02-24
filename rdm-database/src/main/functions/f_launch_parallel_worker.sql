create or replace function ${stagingSchemaName}.f_launch_parallel_worker(
	i_command text
	, i_context_id ${stagingSchemaName}.parallel_worker.context_id%type
	, i_operation_instance_id ${stagingSchemaName}.parallel_worker.operation_instance_id%type
	, i_notification_channel name
	, i_max_worker_processes integer
	, i_polling_interval interval
	, i_max_run_time interval
)
returns name
language plpgsql
volatile
as $function$
declare
	l_worker_num ${stagingSchemaName}.parallel_worker.worker_num%type;
	l_worker_name name;
	l_db name := current_database();
	l_user name := session_user;
begin
	<<waiting_for_available_worker>>
	loop
		-- Get available worker if any
		update 
			${stagingSchemaName}.parallel_worker
		set 
			start_time = current_timestamp
		where 
			(context_id, operation_instance_id, worker_num) = ( 
				select 
					context_id, operation_instance_id, worker_num
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
			)
		returning 
			worker_num		
		into 
			l_worker_num
		;
	
		-- Create new worker within the total worker count limit
		if l_worker_num is null then
			insert into 
				${stagingSchemaName}.parallel_worker(
					context_id
					, operation_instance_id
					, worker_num
					, start_time
				)
			select
				i_context_id 
				, i_operation_instance_id
				, worker_num
				, current_timestamp			
			from (
				select (
					select 
						count(*)
					from 
						${stagingSchemaName}.parallel_worker
					where 
						context_id = i_context_id
						and operation_instance_id = i_operation_instance_id
				) + 1 as worker_num
			) w 
			where 
				worker_num <= i_max_worker_processes 
			returning 
				worker_num		
			into 
				l_worker_num
			;
		end if;
	
		if l_worker_num is not null 
		then 
			raise notice 'Available worker found: %', l_worker_num;
			exit waiting_for_available_worker;
		else	
			if not ${stagingSchemaName}.f_wait_for_parallel_process_completion(
				i_context_id => i_context_id
				, i_operation_instance_id => i_operation_instance_id
				, i_notification_channel => i_notification_channel
				, i_polling_interval => i_polling_interval
				, i_max_run_time => i_max_run_time
			)
			then 
				raise exception 
					'There are no available parallel workers'
				;		
			end if;
		end if;
	end loop waiting_for_available_worker;

	l_worker_name := 
		${stagingSchemaName}.f_parallel_worker_name(
			i_context_id => i_context_id
			, i_operation_instance_id => i_operation_instance_id
			, i_worker_num => l_worker_num
		)
		;
	
	if not (
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
	end if;

	if ${dbms_extension.dblink.schema}.dblink_send_query(
		l_worker_name
		, i_command
	) != 1 
	then
		raise exception 
			'Error sending command to the worker: %: %'
			, l_worker_name
			, i_command
		;
	end if;

	return
		l_worker_name
	;
end
$function$;	

comment on function ${stagingSchemaName}.f_launch_parallel_worker(
	text
	, ${stagingSchemaName}.parallel_worker.context_id%type
	, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
	, name
	, integer
	, interval
	, interval
) is 'Параллельная обработка. Запустить рабочий процесс многопоточной операции'
;
