create or replace function f_is_meta_type_has_localization(
	i_meta_type_id ${database.defaultSchemaName}.meta_type.id%type
)
returns boolean
language sql
stable
as $function$
select 
	case when exists (
			select 
				1
			from 
				${database.defaultSchemaName}.meta_attribute a
			where
				a.master_id = t.id
				and a.is_localisable = true
		) or (
			t.super_type_id is not null
			and ${database.defaultSchemaName}.f_is_meta_type_has_localization(
				i_meta_type_id => t.super_type_id 
			)
		)
		then true
		else false
	end
from 
	${database.defaultSchemaName}.meta_type t
where
	t.id = i_meta_type_id
$function$;		