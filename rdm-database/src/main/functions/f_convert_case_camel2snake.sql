create or replace function f_convert_case_camel2snake(
	i_str text
)
returns text
language sql
immutable
parallel safe
as $function$
select 
	lower(
		regexp_replace(
			i_str
			, '([^_]+?)([A-Z]+)(.*)'
			, '\1_\2\3'
			, 'g'
		)
	)
$function$
;		

comment on function f_convert_case_camel2snake(
	text	
) is 'Преобразование стиля написания текста из "CamelCase" в "snake_case"'
;

create or replace function ${stagingSchemaName}.f_convert_case_camel2snake(
	i_str text
)
returns text
language sql
immutable
parallel safe
as $function$
select 
	${mainSchemaName}.f_convert_case_camel2snake(
		i_str => i_str
	)
$function$
;		

comment on function ${stagingSchemaName}.f_convert_case_camel2snake(
	text	
) is 'Преобразование стиля написания текста из "CamelCase" в "snake_case"'
;
