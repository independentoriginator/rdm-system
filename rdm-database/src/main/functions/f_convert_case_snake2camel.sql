create or replace function f_convert_case_snake2camel(
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
$function$;		