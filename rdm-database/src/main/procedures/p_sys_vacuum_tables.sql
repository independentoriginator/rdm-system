create or replace procedure p_sys_vacuum_tables(
	i_schema_name name 
	, i_table_name name = null
	, i_vacuum_full boolean = false
	, i_thread_max_count integer = 10
	, i_scheduler_type_name text = null
	, i_scheduled_task_name text = null
	, i_scheduled_task_stage_ord_pos integer = 0
	, i_wait_for_delay_in_seconds integer = 1
)
language plpgsql
as $procedure$
declare 
	l_commands text[];
	l_vacuum_full text := case when i_vacuum_full then 'full, ' else '' end;
begin
	select
		array_agg(
			format(
				'vacuum (%sanalyze) %I.%I'
				, l_vacuum_full 
				, t.schema_name
				, t.table_name
			)
			order by 
				t.n_total_relation_size desc
		)			
	into 
		l_commands
	from 
		${mainSchemaName}.v_sys_table_size t
	where 
		t.schema_name = i_schema_name
		and (t.table_name = i_table_name or i_table_name is null)
	;

	if l_commands is not null 
	then 
		call ${stagingSchemaName}.p_execute_in_parallel(
			i_commands => l_commands
			, i_thread_max_count => i_thread_max_count
			, i_scheduler_type_name => i_scheduler_type_name
			, i_scheduled_task_name => i_scheduled_task_name
			, i_scheduled_task_stage_ord_pos => i_scheduled_task_stage_ord_pos
			, i_iteration_number => 0
			, i_wait_for_delay_in_seconds => i_wait_for_delay_in_seconds 
		);	
	end if;
end
$procedure$;

comment on procedure p_sys_vacuum_tables(
	name 
	, name
	, boolean
	, integer
	, text
	, text
	, integer
	, integer
) is 'Вакуумирование таблиц';