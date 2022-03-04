create or replace function trf_meta_type_before_update()
returns trigger
language plpgsql
as $$
begin
	if new.is_abstract = false and new.is_primitive = false then 
		new.is_built = false;
	end if;
	
	call ${mainSchemaName}.p_invalidate_type_descendants_built_flag(i_type_id => new.id);	
	
	return new;
end
$$;			
