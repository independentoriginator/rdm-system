create or replace procedure p_refresh_materialized_views(
	i_refresh_all boolean = false
	, i_schema_name ${mainSchemaName}.meta_schema.internal_name%type = null
	, i_thread_max_count integer = 10
	, i_scheduler_type_name text = null
	, i_scheduled_task_name text = null
	, i_async_mode boolean = false
	, i_wait_for_delay_in_seconds integer = 1
)
language plpgsql
as $procedure$
declare 
	l_view_ids ${type.id}[];
	l_view_names text;
	l_view_refresh_commands text[];
	l_iteration_number integer := 0;
	l_start_timestamp timestamp := clock_timestamp();
	l_timestamp timestamp;
begin
	if i_refresh_all then 
		update ${mainSchemaName}.meta_view
		set is_valid = false
		where is_valid = true;
	end if;
	
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
					format(
						'refresh materialized view %I.%I'
						, t.schema_name 
						, t.internal_name
					) 
				)
			into 
				l_view_ids
				, l_view_names
				, l_view_refresh_commands
			from 
				${mainSchemaName}.v_meta_view t
			where 
				t.is_valid = false
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
							'select id from ${mainSchemaName}.meta_view where id = %s for update; '
							, t.id
						)
						|| format(
							'refresh materialized view %I.%I; '
							, t.schema_name 
							, t.internal_name
						) 
						|| format(
							'update ${mainSchemaName}.meta_view set is_valid = true, refresh_time = current_timestamp where id = %s'
							, t.id
						)
					)
				from 
					${mainSchemaName}.v_meta_view t
				where 
					t.is_valid = false
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
				, i_iteration_number => l_iteration_number
				, i_wait_for_delay_in_seconds => i_wait_for_delay_in_seconds
			);
			
			l_iteration_number := l_iteration_number + 1;
		end loop;
	end if;
end
$procedure$;			
