create or replace function ${stagingSchemaName}.f_meta_view_name(
	i_meta_view_id ${mainSchemaName}.meta_view.id%type
)
returns text
language sql
stable
parallel safe
as $function$
select 
	schema_name || '.' || internal_name as meta_view_name
from
	${mainSchemaName}.v_meta_view
where 
	id = i_meta_view_id
$function$
;	

comment on function ${stagingSchemaName}.f_meta_view_name(
	${mainSchemaName}.meta_view.id%type
) is 'Имя метапредставления'
;