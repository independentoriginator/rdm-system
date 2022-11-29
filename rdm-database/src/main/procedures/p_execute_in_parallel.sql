drop procedure if exists ${stagingSchemaName}.p_execute_in_parallel(text[], integer, text, text, integer, integer, integer);

create or replace procedure ${stagingSchemaName}.p_execute_in_parallel(
	i_commands text[]
	, i_thread_max_count integer = 10
	, i_scheduler_type_name text = null
	, i_scheduled_task_name text = null -- 'project_internal_name.scheduled_task_internal_name'
	, i_scheduled_task_stage_ord_pos integer = null
	, i_iteration_number integer = -1
	, i_wait_for_delay_in_seconds integer = 1
	, i_timeout_in_hours integer = 8
)
language plpgsql
as $procedure$
declare 
	l_connection text;
	l_connections text[];
	l_db name := current_database();
	l_user name := current_user;
	l_command_index integer;
	l_command_count integer;
	l_command text;
	l_last_err_msg text;
	l_msg_text text;
	l_exception_detail text;
	l_exception_hint text;
	l_result text;
	l_bool_result boolean;
	l_start_timestamp timestamp := clock_timestamp();
begin
	if i_scheduler_type_name is not null 
		and i_scheduled_task_name is not null 
		and i_thread_max_count > 1
		and i_iteration_number >= 0
		and exists (
			select 
				1
			from
				information_schema.routines r
			where 
				r.routine_schema = '${stagingSchemaName}'
				and r.routine_name = 'f_execute_in_parallel_with_' || i_scheduler_type_name
				and r.routine_type = 'FUNCTION' 
				and r.data_type = 'boolean'
		)
	then
		execute 
			format('
					select ${stagingSchemaName}.%I(
						i_scheduled_task_name => $1
						, i_scheduled_task_stage_ord_pos => $2
						, i_commands => $3
						, i_iteration_number => $4
						, i_thread_max_count => $5
					)
				'
				, 'f_execute_in_parallel_with_' || i_scheduler_type_name
			)
		into l_bool_result
		using 
			 i_scheduled_task_name
			 , i_scheduled_task_stage_ord_pos
			 , i_commands
			 , i_iteration_number
			 , i_thread_max_count
		;
		if l_bool_result then
			return;
		end if;
	end if;

	l_command_count := cardinality(i_commands);
	l_command_index := array_lower(i_commands, 1);
	
	if i_thread_max_count > 1 
		and exists (
			select 
				1
			from
				pg_catalog.pg_extension e
			where 
				e.extname = 'dblink'
		)
	then
		<<command_loop>>
		while l_command_index <= l_command_count and l_last_err_msg is null loop
			l_connections := array[]::text[];	
		
			for i in 1..least(array_length(i_commands, 1) - l_command_index + 1, i_thread_max_count) loop
				l_connection := '${stagingSchemaName}.p_execute_in_parallel' || i::text;
				
				begin
					if (select coalesce(l_connection = any(${dbms_extension.dblink.schema}.dblink_get_connections()), false)) then 			
						perform ${dbms_extension.dblink.schema}.dblink_disconnect(l_connection);
					end if;
				
					perform ${dbms_extension.dblink.schema}.dblink_connect_u(l_connection, 'dbname=' || l_db || ' user=' || l_user);
		
					l_connections := array_append(l_connections, l_connection);
				exception
				when others then
					if array_length(l_connections, 1) > 0 then		
						get stacked diagnostics
							l_msg_text = MESSAGE_TEXT
							, l_exception_detail = PG_EXCEPTION_DETAIL
							, l_exception_hint = PG_EXCEPTION_HINT
							;
						raise notice 
							'dblink connection error: %: % (hint: %)'
							, l_msg_text
							, l_exception_detail
							, l_exception_hint
							;
					else 
						raise;
					end if;
				end;
			end loop;
			
			if coalesce(array_length(l_connections, 1), 0) = 0 then
				raise exception 'No dblink connections created';
			end if;
		
			<<waiting_for_completion>>
			foreach l_connection in array l_connections loop
				if ${dbms_extension.dblink.schema}.dblink_send_query(l_connection, i_commands[l_command_index]) != 1 then
					while ${dbms_extension.dblink.schema}.dblink_is_busy(l_connection) = 1 loop 
						if extract(hours from clock_timestamp() - l_start_timestamp) >= i_timeout_in_hours then
							l_last_err_msg := 'Timeout occured while waiting for commands completion';
							exit waiting_for_completion;
						end if;
						perform pg_sleep(i_wait_for_delay_in_seconds);
					end loop;
					l_last_err_msg := ${dbms_extension.dblink.schema}.dblink_error_message(l_connection);
					exit waiting_for_completion;
				end if;		
			
				l_command_index := l_command_index + 1;
			end loop;	
			
			if l_last_err_msg is null then
				foreach l_connection in array l_connections loop
					select val 
					into l_result
					from ${dbms_extension.dblink.schema}.dblink_get_result(l_connection) as res(val text)
					;
				end loop;
			end if;	
		
			foreach l_connection in array l_connections loop
				perform ${dbms_extension.dblink.schema}.dblink_disconnect(l_connection);		
			end loop;
		end loop command_loop;
	else
		foreach l_command in array i_commands loop
			execute l_command;
		end loop;	
	end if;
	
	if l_last_err_msg is not null then
		raise exception 'p_execute_in_parallel failure: %', l_last_err_msg;	
	end if;
end
$procedure$;		