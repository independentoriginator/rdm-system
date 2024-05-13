drop procedure if exists p_sys_reindex_tables(
	name 
	, name
	, boolean 
	, integer
	, interval
)
;

create or replace procedure p_sys_reindex_tables(
	i_schema_name name[] 
	, i_table_name name[] = null
	, i_concurrently boolean = false
	, i_max_worker_processes integer = ${max_parallel_worker_processes}
	, i_max_run_time interval = '8 hours'
)
language plpgsql
as $procedure$
begin
	call ${stagingSchemaName}.p_execute_in_parallel(
		i_command_list_query => 
			format(
				$sql$
				select
					format(
						'reindex table %%s%%I.%%I'
						, case when %L::boolean then 'concurrently ' else '' end 
						, t.schema_name
						, t.table_name
					)
				from 
					${mainSchemaName}.v_sys_table_size t
				where 
					t.schema_name = any(string_to_array(%L, ','))%s
				order by 
					t.n_total_relation_size desc
				$sql$
				, i_concurrently
				, array_to_string(i_schema_name, ',')
				, case 
					when i_table_name is not null then 
						format(
							E'\nand t.table_name = any(string_to_array(%L, ','))'
							, array_to_string(i_table_name, ',')
						) 
					else 
						'' 
				end
			)
		, i_context_id => '${mainSchemaName}.p_sys_reindex_tables'::regproc
		, i_max_worker_processes => i_max_worker_processes
		, i_max_run_time => i_max_run_time
	)
	;
end
$procedure$
;

comment on procedure p_sys_reindex_tables(
	name[]
	, name[]
	, boolean 
	, integer
	, interval
) is 'Реиндексация таблиц'
;