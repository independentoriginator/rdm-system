create or replace function f_abbreviate_name(
	i_name text
	, i_adjust_to_max_length boolean = false
	, i_max_length integer = ${mainSchemaName}.f_system_name_max_length()
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
			regexp_replace(t.subname, '[^A-Z]', '', 'g')
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
						rows between current row and unbounded following exclude current row
					)
					, ''
				)
			else ''
		end as target_name
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
where 	
	length(t.target_name) <= i_max_length or i_max_length is null
order by 
	case when i_adjust_to_max_length then t.ordinal_number end  
	, case when not i_adjust_to_max_length then t.ordinal_number end desc
limit 1
$function$;		