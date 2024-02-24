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
	'f_convert_case_snake2camel(text)' as internal_name
	, id as schema_id
	, null as group_id 
	, $sql$
	create or replace function ${mainSchemaName}.f_convert_case_snake2camel(
		i_str text
	)
	returns text
	language sql
	immutable
	parallel safe
	as $function$
	select 
		string_agg(
			upper(left(t.part, 1)) || right(t.part, -1)
			, ''
			order by t.ordinal_number
		) 
	from (
		select 
			sub.part[1] as part
			, sub.ordinal_number
		from
			regexp_matches(
				i_str
				, '_*([^_]+)'
				, 'g'
			) with ordinality as sub(part, ordinal_number) 
	) t
	$function$
	;
	
	comment on function ${mainSchemaName}.f_convert_case_snake2camel(
		text	
	) is 'Преобразование стиля написания текста из "snake_case" в "CamelCase"'
	;
	
	create or replace function ${stagingSchemaName}.f_convert_case_snake2camel(
		i_str text
	)
	returns text
	language sql
	immutable
	parallel safe
	as $function$
	select
		${mainSchemaName}.f_convert_case_snake2camel(
			i_str => i_str
		)
	$function$
	;
	
	comment on function ${stagingSchemaName}.f_convert_case_snake2camel(
		text	
	) is 'Преобразование стиля написания текста из "snake_case" в "CamelCase"'
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
