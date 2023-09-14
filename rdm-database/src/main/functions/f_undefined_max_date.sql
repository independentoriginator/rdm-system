create or replace function f_undefined_max_date()
returns timestamp without time zone
language sql
immutable
parallel safe
as $function$
select 
	to_timestamp('9999-12-31', 'yyyy-mm-dd')::timestamp without time zone
$function$;		

comment on function f_undefined_max_date(
) is 'Условно неопределенная максимальная дата';