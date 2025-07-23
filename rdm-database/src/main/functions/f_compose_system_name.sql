create or replace function 
	f_compose_system_name(
		i_name name
		, i_prefix name = null
		, i_postfix name = null
		, i_delimiter name = '_'
	)
returns name
language sql
immutable
parallel safe
as $function$
select 
	concat_ws(
		coalesce(i_delimiter, '')
		, i_prefix
		, left(
			i_name
			, ${mainSchemaName}.f_system_name_max_length()
				- length(coalesce(i_prefix || coalesce(i_delimiter, ''), ''))
				- length(coalesce(i_postfix || coalesce(i_delimiter, ''), ''))
		)
		, i_postfix
	)::name
$function$
;		
