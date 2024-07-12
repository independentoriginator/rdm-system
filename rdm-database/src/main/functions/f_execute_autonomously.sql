create or replace function 
	${stagingSchemaName}.f_execute_autonomously(
		i_command text
		, i_context_id ${stagingSchemaName}.parallel_worker.context_id%type = 0
		, i_operation_instance_id ${stagingSchemaName}.parallel_worker.operation_instance_id%type = 0
	)
returns void
language plpgsql
volatile
as $function$
declare
	l_worker name
	;
begin
	l_worker :=
		${stagingSchemaName}.f_launch_parallel_worker(
			i_command => i_command
			, i_async_mode => false
			, i_use_notifications => false
			, i_context_id => i_context_id
			, i_operation_instance_id => i_operation_instance_id
		)
	;

	if l_worker is not null then
		perform
		from
			${dbms_extension.dblink.schema}.dblink_disconnect(
				l_worker
			)
		;
	
		delete from 
			${stagingSchemaName}.parallel_worker
		where 
			context_id = i_context_id
			and operation_instance_id = i_operation_instance_id
			and ${stagingSchemaName}.f_parallel_worker_name(
				i_context_id => i_context_id
				, i_operation_instance_id => i_operation_instance_id
				, i_worker_num => worker_num
			) = l_worker
		;
	end if 
	;
	return
	;
end
$function$;	

comment on function 
	${stagingSchemaName}.f_execute_autonomously(
		text
		, ${stagingSchemaName}.parallel_worker.context_id%type
		, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
	) is 'Исполнить команду автономно'
;
