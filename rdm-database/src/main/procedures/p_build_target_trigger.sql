create or replace procedure 
	p_build_target_trigger(
		i_trigger_rec record
	)
language plpgsql
as $procedure$
begin
	if i_trigger_rec.preparation_command is not null then
		execute 
			i_trigger_rec.preparation_command
		;
	end if
	;

	if i_trigger_rec.trigger_id is not null then
		execute 
			format(
				E'create or replace function %I.%s()'
				'\nreturns trigger'
				'\nlanguage plpgsql'
				'\nas $function$'
				'\nbegin'
				'\n	%s'
				'\n	;'
				'\n'
				'\n	return'
				'\n		%s'
				'\n	;'
				'\nend'
				'\n$function$'
				, i_trigger_rec.function_schema_name
				, i_trigger_rec.function_name
				, i_trigger_rec.function_body
				, i_trigger_rec.function_return_expr
			)
		;
	
		execute 
			${mainSchemaName}.f_trigger_creation_command(
				i_trigger_rec => i_trigger_rec
			)
		;
	else
		if i_trigger_rec.target_trigger_id is not null 
			and not (
				i_trigger_rec.event_object_schema = '${mainSchemaName}'
				and i_trigger_rec.event_object_table like 'meta\_%'
			)
		then
			execute 
				format(
					'drop trigger %s on %I.%I'
					, i_trigger_rec.trigger_name
					, i_trigger_rec.event_object_schema
					, i_trigger_rec.event_object_table
				)
			;

			execute 
				format(
					'drop function %I.%I'
					, i_trigger_rec.function_schema_name
					, i_trigger_rec.function_name
				)
			;
		end if
		;	
	end if
	;
end
$procedure$
;	

comment on procedure 
	p_build_target_trigger(
		record
	) is 'Генерация целевого триггера'
;
