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
	'f_abbreviate_name(text,boolean,integer,integer)' as internal_name
	, id as schema_id
	, null as group_id 
	, $sql$
	drop function if exists ${mainSchemaName}.f_abbreviate_name(
		text
		, boolean
		, integer
	);
	
	create or replace function ${mainSchemaName}.f_abbreviate_name(
		i_name text
		, i_adjust_to_max_length boolean = false
		, i_max_length integer = ${mainSchemaName}.f_system_name_max_length()
		, i_leave_last_characters integer = 0
	)
	returns text
	language sql
	immutable
	parallel safe
	as $function$
	select 	
		t.target_name
	from (
		select 
			0 as ordinal_number
			, i_name as target_name
		where 
			i_adjust_to_max_length
		union all
		select 
			t.ordinal_number
			, string_agg(
				regexp_replace(t.subname, '[^A-Z/]', '', 'g')
				|| case 
					when coalesce(i_leave_last_characters, 0) > 0 then
						substring(
							t.subname
							, '[A-Z]([^A-Z]{' || i_leave_last_characters::text || '})[^A-Z]*$'
						) 
					else ''
				end
				, '_'
			) over(
				order by 
					t.ordinal_number
			)
			|| case 
				when i_adjust_to_max_length then 
					coalesce(
						'_' 
						|| string_agg(
							t.subname
							, '_'
						) over(
							order by 
								t.ordinal_number
							rows between 1 following and unbounded following
						)
						, ''
					)
				else ''
			end as target_name
		from ( 
			select 
				upper(left(t.subname, 1)) || right(t.subname, -1) as subname 
				, t.ordinal_number
			from ( 
				select 
					name[1] as subname
					, sub.ordinal_number
				from 
					regexp_matches(
						i_name
						, '_*([^_]+)'
						, 'g'
					) with ordinality as sub(name, ordinal_number)
			) t
		) t
	) t
	where 	
		length(t.target_name) <= i_max_length or i_max_length is null
	order by 
		case when i_adjust_to_max_length then t.ordinal_number end  
		, case when not i_adjust_to_max_length then t.ordinal_number end desc
	limit 1
	$function$
	;	
	
	comment on function ${mainSchemaName}.f_abbreviate_name(
		text
		, boolean
		, integer
		, integer
	) is 'Преобразование наименования в аббревиатуру'
	;
	
	drop function if exists ${stagingSchemaName}.f_abbreviate_name(
		text
		, boolean
		, integer
	);
	
	create or replace function ${stagingSchemaName}.f_abbreviate_name(
		i_name text
		, i_adjust_to_max_length boolean = false
		, i_max_length integer = ${stagingSchemaName}.f_system_name_max_length()
		, i_leave_last_characters integer = 0
	)
	returns text
	language sql
	immutable
	parallel safe
	as $function$
	select 	
		 ${mainSchemaName}.f_abbreviate_name(
			i_name => i_name
			, i_adjust_to_max_length => i_adjust_to_max_length
			, i_max_length => i_max_length
			, i_leave_last_characters => i_leave_last_characters
		)
	$function$
	;
	
	comment on function ${stagingSchemaName}.f_abbreviate_name(
		text
		, boolean
		, integer
		, integer
	) is 'Преобразование наименования в аббревиатуру'
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
