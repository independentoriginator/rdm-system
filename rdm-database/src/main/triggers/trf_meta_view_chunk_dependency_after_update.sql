create or replace function 
	trf_meta_view_chunk_dependency_after_update()
returns trigger
language plpgsql
as $$
begin
	update 
		${mainSchemaName}.meta_view
	set 
		is_created = false
	where 
		id = new.view_id
		or id = old.view_id
		or id = new.master_view_id
		or id = old.master_view_id
	;
	
	return 
		null
	;
end
$$
;		