create or replace function f_trigger_creation_command(
	i_trigger_rec record
	, i_schema_name name = null
	, i_table_name name = null
)
returns text
language plpgsql
immutable
parallel safe
as $function$
begin
	return 
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
			, coalesce(i_schema_name, i_trigger_rec.event_object_schema)
			, coalesce(i_table_name, i_trigger_rec.event_object_table)
			, case when i_trigger_rec.action_reference_old_table is not null then ' old table as ' || i_trigger_rec.action_reference_old_table else '' end
			, case when i_trigger_rec.action_reference_new_table is not null then ' new table as ' || i_trigger_rec.action_reference_new_table else '' end
			, i_trigger_rec.action_orientation
			, i_trigger_rec.function_schema_name
			, i_trigger_rec.function_name
		)
	;
end
$function$
;	

comment on function 
	f_trigger_creation_command(
		record
		, name
		, name
	) is 'Сгенерировать команду создания триггера'
;