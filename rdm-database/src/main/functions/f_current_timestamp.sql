create or replace function f_current_timestamp()
returns timestamp
language sql
immutable
parallel safe
as $function$
select 
	(current_timestamp at time zone current_setting('log_timezone'))::timestamp
$function$;	