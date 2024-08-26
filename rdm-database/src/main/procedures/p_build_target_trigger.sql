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
			, i_trigger_rec.event_object_schema
			, i_trigger_rec.function_name
			, i_trigger_rec.function_body
			, i_trigger_rec.function_return_expr
		)
	;

	execute 
		format(
			E'create or replace trigger %s'
			'\n%s %s'
			'\non %I.%I'
			'\nreferencing%s%s'
			'\nfor each %s'
			'\nexecute function %I.%s()'
			, i_trigger_rec.trigger_name
			, i_trigger_rec.action_timing
			, i_trigger_rec.event_manipulation
			, i_trigger_rec.event_object_schema
			, i_trigger_rec.event_object_table
			, case when i_trigger_rec.action_reference_old_table is not null then ' old table as ' || i_trigger_rec.action_reference_old_table else '' end
			, case when i_trigger_rec.action_reference_new_table is not null then ' new table as ' || i_trigger_rec.action_reference_new_table else '' end
			, i_trigger_rec.action_orientation
			, i_trigger_rec.event_object_schema
			, i_trigger_rec.function_name
		)
	;
end
$procedure$
;	

comment on procedure 
	p_build_target_trigger(
		record
	) is 'Генерация целевого триггера'
;
