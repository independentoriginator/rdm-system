create or replace function f_indent_text(
	i_text text
	, i_indentation_level integer
)
returns text
language sql
immutable
parallel safe
as $function$
select 
	case 
		when i_indentation_level > 0 then
			replace(
				i_text
				, E'\n'
				, E'\n' || repeat(E'\t', i_indentation_level)
			)
		when i_indentation_level < 0 then
			replace(
				i_text
				, E'\n' || repeat(E'\t', abs(i_indentation_level))
				, E'\n'
			)
		else i_text		
	end
$function$;	

comment on function f_indent_text(
	text
	, integer
) is 'Сместить текст';