create or replace function trf_meta_index_column_after_update()
returns trigger
language plpgsql
as $$
begin
	update ${mainSchemaName}.meta_type
	set is_built = false
	where id = (
		select 
			master_id 
		from 
			${mainSchemaName}.meta_index 
		where 
			id = old.master_id
	);
end
$$;			
