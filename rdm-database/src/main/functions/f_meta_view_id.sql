create or replace function ${stagingSchemaName}.f_meta_view_id(
	i_internal_name ${mainSchemaName}.meta_view.internal_name%type
	, i_schema_name ${mainSchemaName}.meta_schema.internal_name%type
)
returns ${mainSchemaName}.meta_view.id%type
language sql
stable
parallel safe
as $function$
select 
	v.id as meta_view_id
from 
	${mainSchemaName}.meta_view v
left join ${mainSchemaName}.meta_schema s
	on s.id = v.schema_id
where 
	v.internal_name = i_internal_name
	and coalesce(s.internal_name, '${mainSchemaName}') = i_schema_name
$function$
;	

comment on function ${stagingSchemaName}.f_meta_view_id(
	${mainSchemaName}.meta_view.internal_name%type
	, ${mainSchemaName}.meta_schema.internal_name%type
) is 'Идентификатор метапредставления'
;