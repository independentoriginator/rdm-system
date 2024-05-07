drop function if exists ${stagingSchemaName}.f_wait_for_parallel_process_completion(
	${stagingSchemaName}.parallel_worker.context_id%type
	, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
	, name
	, text
	, interval
	, interval
);

drop function if exists ${stagingSchemaName}.f_wait_for_parallel_process_completion(
	${stagingSchemaName}.parallel_worker.context_id%type
	, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
	, name
	, name
	, interval
	, interval
);

create or replace function ${stagingSchemaName}.f_wait_for_parallel_process_completion(
	i_context_id ${stagingSchemaName}.parallel_worker.context_id%type
	, i_operation_instance_id ${stagingSchemaName}.parallel_worker.operation_instance_id%type
	, i_wait_for_the_first_one_to_complete boolean
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
	l_workers_opened jsonb[];
	l_workers_completed jsonb[];
	l_worker jsonb;
	l_worker_name name;
	l_err_msg text;
	l_start_timestamp timestamp := clock_timestamp();
begin
	select 
		array_agg(
			jsonb_build_object(
				'num'
				, pw.worker_num
				, 'name'
				, pw.worker_name
				, 'async_mode'
				, pw.async_mode
			)
		)
	into 
		l_workers_opened
	from (
		select 
			pw.worker_num
			, ${stagingSchemaName}.f_parallel_worker_name(
				i_context_id => pw.context_id
				, i_operation_instance_id => pw.operation_instance_id
				, i_worker_num => pw.worker_num
			) as worker_name
			, pw.async_mode
		from 
			${stagingSchemaName}.parallel_worker pw
		where
			pw.context_id = i_context_id
			and pw.operation_instance_id = i_operation_instance_id
	) pw
	join unnest(${dbms_extension.dblink.schema}.dblink_get_connections()) conn(name)
		on conn.name = pw.worker_name
	;	
	
	if cardinality(l_workers_opened) > 0 
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
								unnest(l_workers_opened) worker_obj
							join lateral jsonb_to_record(worker_obj) worker(num integer, name text) on true 
							join ${dbms_extension.dblink.schema}.dblink_get_notify(i_listener_worker) n
								on n.notify_name = i_notification_channel
								and n.extra = worker.num::text
						)
					returning 
						worker_num
						, async_mode
				)
			select 
				array_agg(
					jsonb_build_object(
						'num'
						, worker_num
						, 'name'
						, ${stagingSchemaName}.f_parallel_worker_name(
							i_context_id => i_context_id
							, i_operation_instance_id => i_operation_instance_id
							, i_worker_num => worker_num
						)
						, 'async_mode'
						, async_mode
					)
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
					if (l_worker->>'async_mode')::boolean then
						perform
						from
							${dbms_extension.dblink.schema}.dblink_get_result(
								l_worker->>'name'
							) as res(val text)
						;
					end if;
				end loop;
			
				if i_wait_for_the_first_one_to_complete then
					return 
						true;
				else 
					if not exists (
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
						return 
							true;
					end if;
				end if;
			end if;
		
			call ${mainSchemaName}.p_delay_execution(
				i_delay_interval => i_polling_interval
				, i_max_run_time => i_max_run_time
				, i_start_timestamp => l_start_timestamp
			);	
		
			<<asking_for_an_error>>
			foreach l_worker in array l_workers_opened
			loop
				l_worker_name := l_worker->>'name'
				;
			
				if (l_worker->>'async_mode')::boolean then
					if 
						${dbms_extension.dblink.schema}.dblink_is_busy(
							l_worker_name
						) = 1 
					then
						continue asking_for_an_error; 	
					end if;		
				end if;
			
				l_err_msg := 
					nullif(
						${dbms_extension.dblink.schema}.dblink_error_message(
							l_worker_name
						)
						, 'OK'
					)
				;
			
				if l_err_msg is not null then
					<<cancelling_the_task>>
					foreach l_worker in array l_workers_opened
					loop
						perform
							${dbms_extension.dblink.schema}.dblink_cancel_query(
								l_worker->>'name'
							)
						;
					end loop cancelling_the_task;
				
					raise exception 
						'Parallel worker % failure: %'
						, l_worker_name
						, l_err_msg
					;
				end if;
			end loop asking_for_an_error;
		
			-- Listener activity immitation
			if i_listener_worker is not null then
				perform 
					${dbms_extension.dblink.schema}.dblink_exec(
						i_listener_worker
						, format(
							$plpgsql$do $$ begin perform 'Listening the channel %s'; end $$$plpgsql$
							, i_notification_channel
						)
					)
				;
			end if;		
		
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
	, boolean
	, name
	, name
	, interval
	, interval
) is 'Параллельная обработка. Ожидать завершения рабочего процесса'
;
