create or replace function ${stagingSchemaName}.f_execute_in_parallel_context_specific(
	i_scheduled_task_name text -- 'project_internal_name.scheduled_task_internal_name'
	, i_commands text[]
	, i_iteration_number integer = 0
	, i_thread_max_count integer = 10
)
returns boolean
language plpgsql
stable
as $function$
begin
	-- Context specific realization is expected here
	return false;
end
$function$;