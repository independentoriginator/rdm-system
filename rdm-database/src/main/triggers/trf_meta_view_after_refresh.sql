create or replace function trf_meta_view_after_refresh()
returns trigger
language plpgsql
as $$
begin
	update ${mainSchemaName}.meta_view meta_view
	set 
		is_valid = false
	from 
		${mainSchemaName}.meta_view_dependency dep
	where
		dep.master_view_id = old.id
		and dep.view_id = meta_view.id 
		and meta_view.is_valid = true
	;

	return null;
end
$$;			
