create or replace function f_undefined_min_date()
returns timestamp without time zone
language sql
immutable
parallel safe
as $function$
select 
	to_timestamp('1900-01-01', 'yyyy-mm-dd')::timestamp without time zone
$function$;		