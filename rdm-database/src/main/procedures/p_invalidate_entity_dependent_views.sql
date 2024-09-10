create or replace procedure p_invalidate_entity_dependent_views(
	i_type_id ${mainSchemaName}.meta_type.id%type
)
language plpgsql
as $procedure$
begin
	with 
		dependent_view as (
			select 
				v.id
			from 
				${mainSchemaName}.meta_view_dependency d
			join ${mainSchemaName}.meta_view v
				on v.id = d.view_id
				and v.is_valid = true
			where
				d.master_type_id = i_type_id
			order by 
				v.id
			for update of v
		)
	update 
		${mainSchemaName}.meta_view v
	set 
		is_valid = false
	from 
		dependent_view d
	where
		v.id = d.id
	;
end
$procedure$;

comment on procedure p_invalidate_entity_dependent_views(
	${mainSchemaName}.meta_type.id%type
) is 'Пометить как недействительные зависимые представления сущности';