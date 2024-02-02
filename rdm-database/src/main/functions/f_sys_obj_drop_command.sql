create or replace function f_sys_obj_drop_command(
	i_obj_id ${mainSchemaName}.v_sys_obj.obj_id%type
	, i_cascade boolean = false
	, i_check_existence boolean = false
)
returns text
language sql
stable
as $function$
select
	format('
		drop %s%s %I.%I%s
		'
		, o.obj_specific_type
		, case when i_check_existence then ' if exists' else '' end
		, o.obj_schema
		, o.obj_name
		, case when i_cascade then ' cascade' else ' restrict' end 
	)
from 
	${mainSchemaName}.v_sys_obj o
where 
	o.obj_id = i_obj_id
$function$;

comment on function f_sys_obj_drop_command(
	${mainSchemaName}.v_sys_obj.obj_id%type
	, boolean
	, boolean	
) is 'Составление команды на удаление системного объекта';