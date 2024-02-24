create or replace function ${stagingSchemaName}.f_wait_for_parallel_process_completion(
	i_context_id ${stagingSchemaName}.parallel_worker.context_id%type
	, i_operation_instance_id ${stagingSchemaName}.parallel_worker.operation_instance_id%type
	, i_notification_channel name
	, i_notification_key text
	, i_polling_interval interval
	, i_max_run_time interval
)
returns boolean
language plpgsql
volatile
as $function$
declare 
	l_got_notification boolean := false;
	l_start_timestamp timestamp := clock_timestamp();
begin
	<<waiting_for_notification>>
	loop
		update 
			${stagingSchemaName}.parallel_worker
		set 
			start_time = null
		where 
			(context_id, operation_instance_id, worker_num) = ( 
				select 
					context_id
					, operation_instance_id
					, worker_num
				from (
						select
							context_id
							, operation_instance_id
							, worker_num
							, ${stagingSchemaName}.f_parallel_worker_name(
								i_context_id => context_id
								, i_operation_instance_id => operation_instance_id
								, i_worker_num => worker_num
							) as worker_name					
						from 
							${stagingSchemaName}.parallel_worker 
						where 
							context_id = i_context_id
							and operation_instance_id = i_operation_instance_id
					) w
					, ${dbms_extension.dblink.schema}.dblink_get_notify(w.worker_name) n
				where 
					n.notify_name = i_notification_channel
					and (n.extra = i_notification_key or i_notification_key is null)
			)
		;
	
		l_got_notification := found;
	
		exit waiting_for_notification 
			when l_got_notification
			;
	
		perform	
			pg_catalog.pg_sleep_for(
				i_polling_interval
			)
			;
		
		if clock_timestamp() - l_start_timestamp >= i_max_run_time then
			raise exception
				'Timeout occured while waiting for the parallel worker notifications'
			;
		end if;
	end loop waiting_for_notification;

	return 
		l_got_notification
	;
end
$function$;	

comment on function ${stagingSchemaName}.f_wait_for_parallel_process_completion(
	${stagingSchemaName}.parallel_worker.context_id%type
	, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
	, name
	, text
	, interval
	, interval
) is 'Параллельная обработка. Ожидать завершения рабочего процесса'
;
