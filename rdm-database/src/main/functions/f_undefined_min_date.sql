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
	'f_undefined_min_date()' as internal_name
	, id as schema_id
	, null as group_id 
	, $sql$
	create or replace function ${mainSchemaName}.f_undefined_min_date()
	returns timestamp without time zone
	language sql
	immutable
	parallel safe
	as $function$
	select 
		to_timestamp('1900-01-01', 'yyyy-mm-dd')::timestamp without time zone
	$function$;		
	
	comment on function ${mainSchemaName}.f_undefined_min_date(
	) is 'Условно неопределенная минимальная дата';
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