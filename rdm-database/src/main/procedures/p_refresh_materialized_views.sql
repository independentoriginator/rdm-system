drop procedure if exists p_refresh_materialized_views(
	boolean
	, ${mainSchemaName}.meta_schema.internal_name%type
	, integer
	, text
	, text
	, integer
	, boolean
	, integer
);

create or replace procedure p_refresh_materialized_views(
	i_refresh_all boolean = false
	, i_schema_name ${mainSchemaName}.meta_schema.internal_name%type = null
	, i_thread_max_count integer = ${max_parallel_worker_processes}
	, i_scheduler_type_name text = null
	, i_scheduled_task_name text = null
	, i_scheduled_task_stage_ord_pos integer = 0
	, i_async_mode boolean = false
	, i_wait_for_delay_in_seconds integer = 1
	, i_unpopulated_only boolean = false
)
language plpgsql
security definer
as $procedure$
declare 
	l_view_ids ${type.id}[];
	l_view_names text;
	l_view_refresh_commands text[];
	l_start_timestamp timestamp := clock_timestamp();
	l_timestamp timestamp;
	l_iteration_number integer = 0;
begin
	if i_refresh_all then 
		update ${mainSchemaName}.meta_view
		set is_valid = false
		where is_valid = true;
	end if;

	call ${stagingSchemaName}.p_execute_in_parallel(
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
						extra_info::${type.id} as view_id
					from 
						${stagingSchemaName}.parallel_worker
					where 
						context_id = $1
						and operation_instance_id = $2
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
		, i_context_id => 0
		-- ${mainSchemaName}.p_refresh_materialized_views()::regprocedure::integer
		, i_operation_instance_id => 0
		-- for example, pg_backend_pid() 
		, i_max_worker_processes => i_thread_max_count
		, i_polling_interval => '10 seconds'
		, i_max_run_time => '8 hours'
	)
	;

	/*
	if not i_async_mode then
		while true
		loop
			select
				array_agg(t.id)
				, string_agg(
					t.schema_name || '.' || t.internal_name
					, ', '
				)
				, array_agg(
					case 
						when t.is_matview_emulation then 
							format(
								'call %I.p_refresh_%I()'
								, t.schema_name
								, t.internal_name
							) 
						else 
							${mainSchemaName}.f_materialized_view_refresh_command(
								i_schema_name => t.schema_name
								, i_internal_name => t.internal_name
								, i_has_unique_index => t.has_unique_index
								, i_is_populated => t.is_populated
							)
					end
				)
			into 
				l_view_ids
				, l_view_names
				, l_view_refresh_commands
			from 
				${mainSchemaName}.v_meta_view t
			where 
				t.is_valid = false 
				and (t.is_populated = false or i_unpopulated_only = false)
				and t.is_materialized = true
				and coalesce(t.is_disabled, false) = false
			group by 
				t.dependency_level
			order by 
				t.dependency_level
			limit 1
			;
	
			if l_view_ids is null then
				exit;
			end if;

			perform
			from 
				${mainSchemaName}.meta_view 
			where 
				id = any(l_view_ids)
			for update
			;
			
	   		raise notice 'Refreshing materialized view(s): %...', l_view_names;
	   		
	   		l_timestamp := clock_timestamp();
	   	
			call ${stagingSchemaName}.p_execute_in_parallel(
				i_commands => l_view_refresh_commands
				, i_thread_max_count => i_thread_max_count
				, i_scheduler_type_name => i_scheduler_type_name
				, i_scheduled_task_name => i_scheduled_task_name
				, i_scheduled_task_stage_ord_pos => i_scheduled_task_stage_ord_pos
				, i_iteration_number => l_iteration_number
				, i_wait_for_delay_in_seconds => i_wait_for_delay_in_seconds 
			);
			
			update 
				${mainSchemaName}.meta_view 
			set 
				is_valid = true
				, refresh_time = current_timestamp
			where 
				id = any(l_view_ids)
			;			
			
			l_iteration_number := l_iteration_number + 1;
				
	        raise notice 'Done in %', clock_timestamp() - l_timestamp;
		end loop;
		
		raise notice 'Total time spent: %', clock_timestamp() - l_start_timestamp;
	else
		for 
			l_view_ids
			, l_view_names
			, l_view_refresh_commands
			in (
				select
					array_agg(t.id)
					, string_agg(
						t.schema_name || '.' || t.internal_name
						, ', '
					)
					, array_agg(
						format(
							'call ${mainSchemaName}.p_refresh_materialized_view(i_view_id => %s)'
							, t.id
						)
					)
				from 
					${mainSchemaName}.v_meta_view t
				where 
					t.is_valid = false
					and (t.is_populated = false or i_unpopulated_only = false)
					and t.is_materialized = true
					and coalesce(t.is_disabled, false) = false
				group by 
					t.dependency_level
				order by 
					t.dependency_level
			) 
		loop
			perform
			from 
				${mainSchemaName}.meta_view 
			where 
				id = any(l_view_ids)
			for update
			;
			
			call ${stagingSchemaName}.p_execute_in_parallel(
				i_commands => l_view_refresh_commands
				, i_thread_max_count => i_thread_max_count
				, i_scheduler_type_name => i_scheduler_type_name
				, i_scheduled_task_name => i_scheduled_task_name
				, i_scheduled_task_stage_ord_pos => i_scheduled_task_stage_ord_pos
				, i_iteration_number => l_iteration_number
				, i_wait_for_delay_in_seconds => i_wait_for_delay_in_seconds
			);
			
			l_iteration_number := l_iteration_number + 1;
		end loop;
	end if;
	*/
end
$procedure$;			

comment on procedure p_refresh_materialized_views(
	boolean
	, ${mainSchemaName}.meta_schema.internal_name%type
	, integer
	, text
	, text
	, integer
	, boolean
	, integer
	, boolean
) is 'Обновить материализованные представления';