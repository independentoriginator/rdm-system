insert into meta_view(
	internal_name
	, schema_id
	, group_id
	, query
	, creation_order
	, is_routine
	, is_external
	, is_disabled
)
select 
	'f_convert_case_camel2snake(text)' as internal_name
	, id as schema_id
	, null as group_id 
	, $sql$
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
	$sql$ as query
	, -1000 as creation_order
	, true as is_routine
	, false as is_external
	, false as is_disabled
from 
	meta_schema 
where 
	internal_name = '${mainSchemaName}'
on conflict (internal_name, schema_id)
	do update set
		group_id = excluded.group_id
		, query = excluded.query
		, creation_order = excluded.creation_order
		, is_routine = excluded.is_routine
		, is_external = excluded.is_external	
		, is_disabled = excluded.is_disabled	
;
