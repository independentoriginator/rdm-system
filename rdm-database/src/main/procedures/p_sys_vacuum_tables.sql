drop procedure if exists 
	p_sys_vacuum_tables(
		name 
		, name
		, boolean
		, integer
		, text
		, text
		, integer
		, integer
	)
;

drop procedure if exists 
	p_sys_vacuum_tables(
		name[]
		, boolean
		, integer
		, interval
		, interval
	)
;

create or replace procedure 
	p_sys_vacuum_tables(
		i_schema_name name[] = null
		, i_vacuum_full boolean = false
		, i_max_worker_processes integer = ${max_parallel_worker_processes}
		, i_polling_interval interval = '10 seconds'
		, i_max_run_time interval = '24 hours'
		, i_exclude_emulated_matviews boolean = false
	)
language plpgsql
as $procedure$
declare 
	l_schema_name name[] := i_schema_name;
begin
	if l_schema_name is null or cardinality(l_schema_name) = 0 then
		select 
			array_agg(internal_name)
		into
			l_schema_name	
		from 
			${mainSchemaName}.meta_schema
		where
			not is_external 
			and not is_disabled			
		;
	end if
	;

	call 
		${stagingSchemaName}.p_execute_in_parallel(
			i_command_list_query => 
				format(
					$sql$
					select
						format(
							'vacuum (%sanalyze) %%I.%%I'
							, t.schema_name
							, t.table_name
						)
					from 
						${mainSchemaName}.f_sys_table_size(
							i_schema_name => string_to_array(%L, ',')
						) t
					where 
						t.table_id not in (
							select 
								o.obj_id							
							from 
								${mainSchemaName}.v_sys_obj o
							where 
								(
									o.obj_schema = '${mainSchemaName}'
									and o.obj_name like 'meta\_%%'
								)
								or o.obj_schema = '${etlRepositorySchemaName}'
								or (
									o.obj_schema = '${stagingSchemaName}'
									and o.obj_name in (
										'parallel_worker'
										, 'scheduled_task_subjob'
									)
								) 
								or (
									%L::boolean
									and o.obj_id in (
										select 	
											v.view_oid
										from 	
											${mainSchemaName}.v_meta_view v
										where
											v.is_matview_emulation
											and v.view_oid is not null
									)
								)
						)
					order by 
						t.n_total_relation_size desc
					$sql$
					, case when i_vacuum_full then 'full, ' else '' end
					, array_to_string(l_schema_name, ',')
					, coalesce(i_exclude_emulated_matviews, false)::varchar
				)
			, i_context_id => '${mainSchemaName}.p_sys_vacuum_tables'::regproc
			, i_use_notifications => false
			, i_max_worker_processes => i_max_worker_processes
			, i_polling_interval => i_polling_interval
			, i_max_run_time => i_max_run_time
			, i_close_process_pool_on_completion => true
		)
	;
end
$procedure$
;

comment on procedure 
	p_sys_vacuum_tables(
		name[]
		, boolean
		, integer
		, interval
		, interval
		, boolean
	) 
	is 'Вакуумирование таблиц'
;