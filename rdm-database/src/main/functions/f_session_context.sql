create or replace function 
	${stagingSchemaName}.f_session_context(
		i_key text
		, i_value text = null
	)
returns text
language sql
as $function$
select 	
	case 
		when i_value is null then	
			current_setting(i_key)
        else 
        	set_config(i_key, i_value, false)
	end	
$function$
;	

comment on function 
	${stagingSchemaName}.f_session_context(
		text
		, text
	) is 'Ключ-значение в контексте сеанса'
;