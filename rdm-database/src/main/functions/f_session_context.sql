create or replace function 
	${stagingSchemaName}.f_session_context(
		i_key text
		, i_value text = null
	)
returns text
language plpgsql
stable
as $function$
begin
	if i_value is null then
		return 
			current_setting(i_key)
		;
	end if
	;
	perform
		set_config(i_key, i_value, false)
	;
	return 
		null
	;
exception
	-- Class 42 — Syntax Error or Access Rule Violation
	-- 42704 - undefined_object
	when sqlstate '42704' then
		return 
			null
		;
end
$function$
;	

comment on function 
	${stagingSchemaName}.f_session_context(
		text
		, text
	) is 'Ключ-значение в контексте сеанса'
;