create or replace function f_server_version()
returns text
language sql
immutable
parallel safe
as $function$
select 
	regexp_replace(version(), '^([^\d]*)(\d{1,2}\.\d{1,2})(.*)', '\2')
$function$;	

comment on function f_server_version(
) is 'Версия сервера';