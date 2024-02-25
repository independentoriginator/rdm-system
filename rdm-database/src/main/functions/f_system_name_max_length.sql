create or replace function f_system_name_max_length()
returns integer
language sql
immutable
parallel safe
as $function$
select
	s.setting::integer 
from 
	pg_catalog.pg_settings s
where 
	s.name = 'max_identifier_length'
$function$
;		

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
	'f_system_name_max_length()' as internal_name
	, id as schema_id
	, null as group_id 
	, $sql$
	create or replace function ${mainSchemaName}.f_system_name_max_length()
	returns integer
	language sql
	immutable
	parallel safe
	as $function$
	select
		s.setting::integer 
	from 
		pg_catalog.pg_settings s
	where 
		s.name = 'max_identifier_length'
	$function$
	;		
	
	comment on function ${mainSchemaName}.f_system_name_max_length(
	) is 'Максимально возможная длина системного имени'
	;

	create or replace function ${stagingSchemaName}.f_system_name_max_length()
	returns integer
	language sql
	immutable
	parallel safe
	as $function$
	select
		${mainSchemaName}.f_system_name_max_length()
	$function$
	;		
	
	comment on function ${stagingSchemaName}.f_system_name_max_length(
	) is 'Максимально возможная длина системного имени'
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
	