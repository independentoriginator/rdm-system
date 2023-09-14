create or replace function ${stagingSchemaName}.f_system_name_max_length()
returns integer
language sql
immutable
parallel safe
as $function$
select
	s.setting::integer 
from 
	pg_catalog.pg_settings s
where 
	s.name = 'max_identifier_length'
$function$;		

comment on function ${stagingSchemaName}.f_system_name_max_length(
) is 'Максимально возможная длина системного имени';