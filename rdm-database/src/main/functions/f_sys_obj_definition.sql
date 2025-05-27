drop function if exists f_sys_obj_definition(
	${mainSchemaName}.v_sys_obj.obj_id%type
	, boolean
);

drop function if exists f_sys_obj_definition(
	${mainSchemaName}.v_sys_obj.obj_id%type
	, boolean
	, boolean
);

drop function if exists f_sys_obj_definition(
	${mainSchemaName}.v_sys_obj.obj_id%type
	, boolean
	, boolean
	, integer	
);

create or replace function f_sys_obj_definition(
	i_obj_class ${mainSchemaName}.v_sys_obj.obj_class%type
	, i_obj_id ${mainSchemaName}.v_sys_obj.obj_id%type
	, i_include_owner boolean = true
	, i_enforce_nodata_for_matview boolean = false
	, i_enforced_compatibility_level integer = null
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
	|| ${mainSchemaName}.f_apply_backward_compatibility_macro(
		i_program_code => 
			case o.obj_class
				when 'relation' then
					case 
						when o.obj_general_type = 'view' then
							${mainSchemaName}.f_view_definition(
								i_view_oid => o.obj_id
								, i_enforce_nodata_for_matview => i_enforce_nodata_for_matview
							)
					end
				when 'routine' then
					pg_catalog.pg_get_functiondef(o.obj_id)
				when 'schema' then
					format(
						'create schema %I'
						, o.obj_name
					)
			end
		, i_compatibility_level => i_enforced_compatibility_level 
	)
	|| case 
		when i_include_owner 
		then E';\nreset role;'::text 
		else ''::text 
	end
from 
	${mainSchemaName}.v_sys_obj o
where 
	o.obj_id = i_obj_id
	and o.obj_class = i_obj_class
$function$;

comment on function f_sys_obj_definition(
	${mainSchemaName}.v_sys_obj.obj_class%type
	, ${mainSchemaName}.v_sys_obj.obj_id%type
	, boolean
	, boolean
	, integer	
) is 'Определение системного объекта';