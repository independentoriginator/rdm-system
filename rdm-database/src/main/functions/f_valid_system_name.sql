drop function if exists f_valid_system_name(
	text
);

create or replace function f_valid_system_name(
	i_raw_name text
	, i_is_considered_as_whole_name	boolean = true
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
				case 
					when i_is_considered_as_whole_name then
						regexp_replace(
							i_raw_name
							, '^(\d){1,1}'
							, '_\1'
						)
					else i_raw_name
				end
				, '[^\w\d\_]+'
				, '_'
				, 'g'
			)
		)
		, ${mainSchemaName}.f_system_name_max_length()
	)::name
$function$;		

insert into 
	meta_view(
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
	'f_valid_system_name(text,boolean)' as internal_name
	, id as schema_id
	, null as group_id 
	, $sql$
	drop function if exists ${stagingSchemaName}.f_valid_system_name(
		text
	);
	drop function if exists ${mainSchemaName}.f_valid_system_name(
		text
	);
	
	create or replace function ${mainSchemaName}.f_valid_system_name(
		i_raw_name text
		, i_is_considered_as_whole_name	boolean = true
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
					case 
						when i_is_considered_as_whole_name then
							regexp_replace(
								i_raw_name
								, '^(\d){1,1}'
								, '_\1'
							)
						else i_raw_name
					end
					, '[^\w\d\_]+'
					, '_'
					, 'g'
				)
			)
			, ${mainSchemaName}.f_system_name_max_length()
		)::name
	$function$
	;		

	comment on function ${mainSchemaName}.f_valid_system_name(
		text
		, boolean
	) is 'Допустимое системное имя'
	;

	create or replace function ${stagingSchemaName}.f_valid_system_name(
		i_raw_name text
		, i_is_considered_as_whole_name	boolean = true
	)
	returns name
	language sql
	immutable
	parallel safe
	as $function$
	select
		${mainSchemaName}.f_valid_system_name(
			i_raw_name => i_raw_name
			, i_is_considered_as_whole_name => i_is_considered_as_whole_name			
		)
	$function$
	;		
	
	comment on function ${stagingSchemaName}.f_valid_system_name(
		text
		, boolean
	) is 'Допустимое системное имя'
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

update 
	${mainSchemaName}.meta_view
set 
	is_disabled = true
where 
	internal_name in (
		'f_valid_system_name(text)'
	)
	and schema_id = (select id from ${mainSchemaName}.meta_schema where internal_name = '${mainSchemaName}')
	and is_disabled = false
;
