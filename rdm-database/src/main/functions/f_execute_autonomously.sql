drop function if exists 
	${stagingSchemaName}.f_execute_autonomously(
		text
		, ${stagingSchemaName}.parallel_worker.context_id%type
		, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
	)
;

create or replace function 
	${stagingSchemaName}.f_execute_autonomously(
		i_command text
		, i_context_id ${stagingSchemaName}.parallel_worker.context_id%type = 0
		, i_operation_instance_id ${stagingSchemaName}.parallel_worker.operation_instance_id%type = 0
	)
returns text
language plpgsql
volatile
as $function$
begin
	return
		${stagingSchemaName}.f_launch_parallel_worker(
			i_command => i_command
			, i_is_oneoff => true
			, i_async_mode => false
			, i_use_notifications => false
			, i_context_id => i_context_id
			, i_operation_instance_id => i_operation_instance_id
		)
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
