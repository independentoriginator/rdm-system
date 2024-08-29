drop procedure if exists 
	p_refresh_materialized_views(
		boolean
		, ${mainSchemaName}.meta_schema.internal_name%type
		, integer
		, text
		, text
		, integer
		, boolean
		, integer
	)
;

drop procedure if exists 
	p_refresh_materialized_views(
		boolean
		, ${mainSchemaName}.meta_schema.internal_name%type
		, integer
		, text
		, text
		, integer
		, boolean
		, integer
		, boolean
	)
;

create or replace procedure 
	p_refresh_materialized_views(
		i_refresh_all boolean = false
		, i_unpopulated_only boolean = false
		, i_max_worker_processes integer = ${max_parallel_worker_processes}
		, i_polling_interval interval = '10 seconds'
		, i_max_run_time interval = '8 hours'
)
language plpgsql
security definer
as $procedure$
begin
	if i_refresh_all then 
		update ${mainSchemaName}.meta_view
		set is_valid = false
		where is_valid = true;
	end if;

	call 
		${stagingSchemaName}.p_execute_in_parallel(
			i_command_list_query => 
				format(
					$sql$
					with 
						materialized_view as (
							select 
								t.*
							from 
								${mainSchemaName}.v_meta_view t
							where 
								t.is_valid = false
								and t.is_materialized = true
								and coalesce(
									t.is_disabled
									, false
								) = false%s
						)
					select
						format(
							'call ${mainSchemaName}.p_refresh_materialized_view(i_view_id => %%s)'
							, refreshable_view.id
						)
						, refreshable_view.id::varchar as extra_info
					from
					(
						select 
							t.id
						from 
							materialized_view t
						except
						select 
							dep.view_id
						from 
							${mainSchemaName}.meta_view_dependency dep
						join materialized_view mv 
							on mv.id = dep.master_view_id
						except 
						select 
							dep.view_id
						from 
							${mainSchemaName}.v_meta_view_orderliness_dependency dep
						join materialized_view mv 
							on mv.id = dep.master_view_id
						except 
						select 
							extra_info::${type.id} as view_id
						from 
							${stagingSchemaName}.parallel_worker
						where 
							context_id = $1
							and operation_instance_id = $2
							and extra_info is not null
							and start_time is not null
					) refreshable_view
					join materialized_view v
						on v.id = refreshable_view.id
					order by 
						v.dependency_level
					$sql$
					, case when i_unpopulated_only then E'\nand t.is_populated = false' else '' end
				)
			, i_do_while_checking_condition =>
				format(
					$sql$
					select 
						not exists (
							select 
								t.id
							from 
								${mainSchemaName}.v_meta_view t
							where 
								t.is_valid = false
								and t.is_materialized = true
								and coalesce(
									t.is_disabled
									, false
								) = false%s
						)
					$sql$
					, case when i_unpopulated_only then E'\nand t.is_populated = false' else '' end
				)
			, i_context_id => '${mainSchemaName}.p_refresh_materialized_views'::regproc
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
	p_refresh_materialized_views(
		boolean
		, boolean
		, integer
		, interval
		, interval
	) is 'Обновить материализованные представления'
;