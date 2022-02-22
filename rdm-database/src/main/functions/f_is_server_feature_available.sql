create or replace function f_is_server_feature_available(
	i_feauture text
)
returns boolean
language sql
immutable
parallel safe
as $function$
select 
	case i_feauture
		when 'cte_explicitly_materializing' then 
			case 
				when trunc(${mainSchemaName}.f_server_version()::numeric, 0) >= 12 then true
				else false
			end
	end
$function$;		