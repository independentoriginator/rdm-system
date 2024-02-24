create or replace function ${stagingSchemaName}.f_parallel_worker_name(
	i_context_id ${stagingSchemaName}.parallel_worker.context_id%type
	, i_operation_instance_id ${stagingSchemaName}.parallel_worker.operation_instance_id%type
	, i_worker_num ${stagingSchemaName}.parallel_worker.worker_num%type
)
returns name
language sql
immutable
parallel safe
as $function$
select 	
	format(
		'${project.artifactId}.parallel_worker.%s.%s.%s'
		, i_context_id
		, i_operation_instance_id
		, i_worker_num
	)
$function$;	

comment on function ${stagingSchemaName}.f_parallel_worker_name(
	${stagingSchemaName}.parallel_worker.context_id%type
	, ${stagingSchemaName}.parallel_worker.operation_instance_id%type
	, ${stagingSchemaName}.parallel_worker.worker_num%type
) is 'Параллельная обработка. Наименование рабочего процесса';
