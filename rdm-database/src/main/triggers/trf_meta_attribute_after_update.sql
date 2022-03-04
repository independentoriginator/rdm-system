create or replace function trf_meta_attribute_after_update()
returns trigger
language plpgsql
as $$
begin
	update ${mainSchemaName}.meta_type
	set is_built = false
	where id = old.master_id
	;
end
$$;			
