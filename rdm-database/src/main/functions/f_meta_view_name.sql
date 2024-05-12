create or replace function ${stagingSchemaName}.f_meta_view_name(
	i_meta_view_id ${mainSchemaName}.meta_view.id%type
)
returns text
language sql
stable
parallel safe
as $function$
select 
	coalesce(s.internal_name, '${mainSchemaName}')
	|| '.' 
	|| v.internal_name 
	as meta_view_name
from 
	${mainSchemaName}.meta_view v
left join ${mainSchemaName}.meta_schema s
	on s.id = v.schema_id
where 
	v.id = i_meta_view_id
$function$
;	

comment on function ${stagingSchemaName}.f_meta_view_name(
	${mainSchemaName}.meta_view.id%type
) is 'Имя метапредставления'
;