drop function is exists f_sys_obj_definition(
	${mainSchemaName}.v_sys_obj.obj_id%type
	, boolean
);

create or replace function f_sys_obj_definition(
	i_obj_id ${mainSchemaName}.v_sys_obj.obj_id%type
	, i_include_owner boolean = true
	, i_enforce_nodata_for_matview boolean = false
)
returns text
language sql
stable
as $function$
select 
	case 
		when i_include_owner 
		then format(E'set role %s;\n'::text, o.obj_owner) 
		else ''::text 
	end 
	|| case o.obj_class
		when 'relation' then 
			${mainSchemaName}.f_view_definition(
				i_view_oid => o.obj_id
				, i_enforce_nodata_for_matview => i_enforce_nodata_for_matview
			)
		when 'routine' then
			pg_catalog.pg_get_functiondef(o.obj_id)
	end
	|| case 
		when i_include_owner 
		then E';\nreset role;'::text 
		else ''::text 
	end
from 
	${mainSchemaName}.v_sys_obj o
where 
	o.obj_id = i_obj_id
$function$;

comment on function f_sys_obj_definition(
	${mainSchemaName}.v_sys_obj.obj_id%type
	, boolean
	, boolean
) is 'Определение системного объекта';