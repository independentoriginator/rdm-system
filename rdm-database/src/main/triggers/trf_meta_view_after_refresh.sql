create or replace function trf_meta_view_after_refresh()
returns trigger
language plpgsql
as $$
begin
	with 
		dependent_view as (
			select 
				v.id
			from 
				${mainSchemaName}.meta_view_dependency dep
			join ${mainSchemaName}.meta_view v 
				on v.id = dep.view_id
			where 
				dep.master_view_id = old.id
				and dep.master_view_id <> dep.view_id 
			for update of v
		)
	update ${mainSchemaName}.meta_view meta_view
	set 
		is_valid = false
	from 
		dependent_view
	where
		dependent_view.id = meta_view.id
	;

	return null;
end
$$;

comment on function trf_meta_view_after_refresh is 'Метапредставление. Триггерная функция для события "После обновления"';
