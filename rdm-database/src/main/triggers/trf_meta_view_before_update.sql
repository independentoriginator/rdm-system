create or replace function trf_meta_view_before_update()
returns trigger
language plpgsql
as $$
begin
	new.is_created = false;
	
	delete from 
		${mainSchemaName}.meta_view_dependency
	where 
		view_id = new.id
	;

	return new;
end
$$;			
