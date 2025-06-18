create or replace function 
	f_host_name()
returns text
language plpgsql
as $function$
begin
	return
		trim(trailing E'\n' from pg_catalog.pg_read_file('/etc/hostname'))
	;
exception
	-- Class 42 — Syntax Error or Access Rule Violation
	-- 42501 insufficient_privilege
	when sqlstate '42501' then
		return
			null
		;
end
$function$
;	