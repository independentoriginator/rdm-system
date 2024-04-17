create or replace function f_valid_system_name(
	i_raw_name text
)
returns name
language sql
immutable
parallel safe
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
	'f_valid_system_name(text)' as internal_name
	, id as schema_id
	, null as group_id 
	, $sql$
	create or replace function ${mainSchemaName}.f_valid_system_name(
		i_raw_name text
	)
	returns name
	language sql
	immutable
	parallel safe
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
	$function$
	;		

	comment on function ${mainSchemaName}.f_valid_system_name(
		text
	) is 'Допустимое системное имя'
	;

	create or replace function ${stagingSchemaName}.f_valid_system_name(
		i_raw_name text
	)
	returns name
	language sql
	immutable
	parallel safe
	as $function$
	select
		${mainSchemaName}.f_valid_system_name(
			i_raw_name => i_raw_name
		)
	$function$
	;		
	
	comment on function ${stagingSchemaName}.f_valid_system_name(
		text
	) is 'Допустимое системное имя'
	;
	$sql$ as query
	, -1001 as creation_order
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