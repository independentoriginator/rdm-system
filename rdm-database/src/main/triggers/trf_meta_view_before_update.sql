create or replace function trf_meta_view_before_update()
returns trigger
language plpgsql
as $$
begin
	new.is_created = false;

	with 
		dependent_view as (
			select 
				v.id
			from 
				${mainSchemaName}.meta_view_dependency dep
			join ${mainSchemaName}.meta_view v 
				on v.id = dep.view_id
				and v.is_created = true
				and v.is_external = false
			where 
				dep.master_view_id = old.id
				and dep.master_view_id <> dep.view_id
			order by 
				v.id
			for update of v
		)
	update 
		${mainSchemaName}.meta_view meta_view
	set 
		is_created = false
	from 
		dependent_view
	where
		dependent_view.id = meta_view.id
	;
	
	return new;
end
$$;			

comment on function trf_meta_view_before_update is 'Метапредставление. Триггерная функция для события "Перед обновлением"';