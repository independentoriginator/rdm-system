drop function if exists ${stagingSchemaName}.f_wait_for_parallel_process_completion(
	${stagingSchemaName}.parallel_worker.context_id%type
	, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
	, name
	, text
	, interval
	, interval
);

create or replace function ${stagingSchemaName}.f_wait_for_parallel_process_completion(
	i_context_id ${stagingSchemaName}.parallel_worker.context_id%type
	, i_operation_instance_id ${stagingSchemaName}.parallel_worker.operation_instance_id%type
	, i_listener_worker name
	, i_notification_channel name
	, i_polling_interval interval
	, i_max_run_time interval
)
returns boolean
language plpgsql
volatile
as $function$
declare 
	l_workers integer[];
	l_workers_completed integer[];
	l_worker integer;
	l_worker_name name;
	l_err_msg text;
	l_start_timestamp timestamp := clock_timestamp();
begin
	select 
		array_agg(worker_num)
	into 
		l_workers
	from 
		${stagingSchemaName}.parallel_worker
	where
		context_id = i_context_id
		and operation_instance_id = i_operation_instance_id
	;
	
	if cardinality(l_workers) > 0 
	then
		<<waiting_for_completion>>
		loop
			with 
				workers_completed as (
					update 
						${stagingSchemaName}.parallel_worker
					set 
						start_time = null
					where
						context_id = i_context_id
						and operation_instance_id = i_operation_instance_id
						and worker_num in (
							select 
								worker.num
							from 
								unnest(l_workers) as worker(num) 
							join ${dbms_extension.dblink.schema}.dblink_get_notify(i_listener_worker) n
								on n.notify_name = i_notification_channel
								and n.extra = worker.num::text
						)
					returning 
						worker_num
				)
			select 
				array_agg(
					worker_num
				)
			into 
				l_workers_completed
			from 
				workers_completed
			;
		
			if cardinality(l_workers_completed) > 0 then
				raise notice 'Have gotten the completion notification';
				
				foreach l_worker in array l_workers_completed
				loop
					perform
					from
						${dbms_extension.dblink.schema}.dblink_get_result(
							${stagingSchemaName}.f_parallel_worker_name(
								i_context_id => i_context_id
								, i_operation_instance_id => i_operation_instance_id
								, i_worker_num => l_worker
							)
						) as res(val text)
					;
				end loop;
			
				return 
					true;
			else
				raise notice 'Have not gotten the notification expected. Will sleep for interval %', i_polling_interval; 
			end if;
		
			call ${mainSchemaName}.p_delay_execution(
				i_delay_interval => i_polling_interval
				, i_max_run_time => i_max_run_time
				, i_start_timestamp => l_start_timestamp
			);	
		
			foreach l_worker in array l_workers
			loop
				l_worker_name :=
					${stagingSchemaName}.f_parallel_worker_name(
						i_context_id => i_context_id
						, i_operation_instance_id => i_operation_instance_id
						, i_worker_num => l_worker
					)
				;
			
				perform
					${dbms_extension.dblink.schema}.dblink_is_busy(
						l_worker_name
					)
				;
			
				l_err_msg := 
					nullif(
						${dbms_extension.dblink.schema}.dblink_error_message(
							l_worker_name
						)
						, 'OK'
					)
				;
			
				if l_err_msg is not null then
					foreach l_worker in array l_workers
					loop
						perform
							${dbms_extension.dblink.schema}.dblink_cancel_query(
								${stagingSchemaName}.f_parallel_worker_name(
									i_context_id => i_context_id
									, i_operation_instance_id => i_operation_instance_id
									, i_worker_num => l_worker
								)
							)
						;
					end loop;
				
					raise exception 
						'Parallel worker % failure: %'
						, l_worker_name
						, l_err_msg
					;
				end if;
			end loop;
		
		end loop waiting_for_completion;
	end if;

	return 
		false
	;
end
$function$;	

comment on function ${stagingSchemaName}.f_wait_for_parallel_process_completion(
	${stagingSchemaName}.parallel_worker.context_id%type
	, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
	, name
	, name
	, interval
	, interval
) is 'Параллельная обработка. Ожидать завершения рабочего процесса'
;
