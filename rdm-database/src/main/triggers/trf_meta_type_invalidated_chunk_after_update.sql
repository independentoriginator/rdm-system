create or replace function 
	trf_meta_type_invalidated_chunk_after_update()
returns trigger
language plpgsql
as $$
begin
	update 
		${mainSchemaName}.meta_type
	set 
		is_built = false
	where 
		id = coalesce(new.type_id, old.type_id)
	;
	
	return 
		null
	;
end
$$
;		
