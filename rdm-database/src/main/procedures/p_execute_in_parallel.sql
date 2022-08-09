create or replace procedure ${stagingSchemaName}.p_execute_in_parallel(
	i_commands text[]
	, i_thread_max_count integer = 10
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
	l_last_err_msg text;
	l_msg_text text;
	l_exception_detail text;
	l_exception_hint text;
	l_result text;
begin
	l_command_count := array_upper(i_commands, 1);
	l_command_index := array_lower(i_commands, 1);

	<<command_loop>>
	while l_command_index <= l_command_count and l_last_err_msg is null loop
		l_connections := array[]::text[];	
	
		for i in 1..least(array_length(i_commands, 1) - l_command_index + 1, i_thread_max_count) loop
			l_connection := '${stagingSchemaName}.p_execute_in_parallel' || i::text;
			
			begin
				if (select coalesce(l_connection = any(dblink_get_connections()), false)) then 			
					perform dblink_disconnect(l_connection);
				end if;
			
				perform dblink_connect_u(l_connection, 'dbname=' || l_db || ' user=' || l_user);
	
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
	
		foreach l_connection in array l_connections loop
			if dblink_send_query(l_connection, i_commands[l_command_index]) != 1 then
				while dblink_is_busy(l_connection) = 1 loop 
					perform pg_sleep(1.0);
				end loop;
				l_last_err_msg := dblink_error_message(l_connection);
				exit;
			end if;		
		
			l_command_index := l_command_index + 1;
		end loop;	
		
		if l_last_err_msg is null then
			foreach l_connection in array l_connections loop
				select val 
				into l_result
				from dblink_get_result(l_connection) as res(val text)
				;
			end loop;
		end if;	
	
		foreach l_connection in array l_connections loop
			perform dblink_disconnect(l_connection);		
		end loop;
	end loop command_loop;
	
	if l_last_err_msg is not null then
		raise exception 'p_execute_in_parallel failure: %', l_last_err_msg;	
	end if;
end
$procedure$;		