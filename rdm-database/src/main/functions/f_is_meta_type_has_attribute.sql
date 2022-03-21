create or replace function f_is_meta_type_has_attribute(
	i_meta_type_id ${mainSchemaName}.meta_type.id%type
	, i_attribute_name ${mainSchemaName}.meta_attribute.internal_name%type
)
returns boolean
language sql
stable
as $function$
select
	coalesce(( 
			select 
				true
			from 
				${mainSchemaName}.meta_attribute a 
			where 
				a.master_id = t.id
				and a.internal_name = i_attribute_name
		)
		, case 
			when t.master_type_id is not null and i_attribute_name = 'master_id' then true
		end
		, case 
			when t.super_type_id is not null then 
				${mainSchemaName}.f_is_meta_type_has_attribute(
					i_meta_type_id => t.super_type_id
					, i_attribute_name => i_attribute_name
				) 
		end
		, false
	)
from 
	${mainSchemaName}.meta_type t
where
	t.id = i_meta_type_id
;
$function$;		