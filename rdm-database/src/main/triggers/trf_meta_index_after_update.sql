create or replace function trf_meta_index_after_update()
returns trigger
language plpgsql
as $$
declare 
	l_type_rec ${mainSchemaName}.meta_type;
begin
	select 
		*
	into 
		l_type_rec 
	from 
		${mainSchemaName}.meta_type
	where 
		id = coalesce(new.master_id, old.master_id)
	;
	
	if l_type_rec.is_abstract = false then
		update ${mainSchemaName}.meta_type
		set is_built = false
		where id = l_type_rec.id
		;
	end if;
		
	call ${mainSchemaName}.p_invalidate_type_descendants_built_flag(i_type_id => l_type_rec.id);
	
	return null;
end
$$;

comment on function trf_meta_index_after_update is 'Метаиндекс. Триггерная функция для события "После обновления"';
