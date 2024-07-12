drop procedure if exists p_sys_reindex_tables(
	name 
	, name
	, boolean 
	, integer
	, interval
)
;

drop procedure if exists p_sys_reindex_tables(
	name[]
	, name[]
	, boolean 
	, integer
	, interval
)
;

create or replace procedure 
	p_sys_reindex_tables(
		i_schema_name name[] 
		, i_concurrently boolean = false
		, i_max_worker_processes integer = ${max_parallel_worker_processes}
		, i_max_run_time interval = '8 hours'
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
			ng_rdm.meta_schema
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
							'reindex table %%s%%I.%%I'
							, case when %L::boolean then 'concurrently ' else '' end 
							, t.schema_name
							, t.table_name
						)
					from 
						${mainSchemaName}.v_sys_table_size t
					where 
						t.schema_name = any(string_to_array(%L, ','))
					order by 
						t.n_total_relation_size desc
					$sql$
					, i_concurrently
					, array_to_string(l_schema_name, ',')
				)
			, i_use_notifications => false
			, i_context_id => '${mainSchemaName}.p_sys_reindex_tables'::regproc
			, i_max_worker_processes => i_max_worker_processes
			, i_max_run_time => i_max_run_time
		)
	;
end
$procedure$
;

comment on procedure 
	p_sys_reindex_tables(
		name[]
		, boolean 
		, integer
		, interval
	) is 'Реиндексация таблиц'
;