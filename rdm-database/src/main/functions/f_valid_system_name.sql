create or replace function f_valid_system_name(
	i_raw_name text
)
returns name
language sql
volatile
as $function$
select 
	left(
		lower(
			regexp_replace(
				regexp_replace(
					i_raw_name
					, '[^\w\d\_]+'
					, '_'
					, 'g'
				)
				, '^(\d){1,1}'
				, '_\1'
			)
		)
		, ${mainSchemaName}.f_system_name_max_length()
	)::name
$function$;		

comment on function f_valid_system_name(
	text
) is 'Допустимое системное имя';