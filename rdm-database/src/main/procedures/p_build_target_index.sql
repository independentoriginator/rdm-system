create or replace procedure p_build_target_index(
	i_index_rec record
)
language plpgsql
as $procedure$
declare 
	l_is_target_index_exists bool := i_index_rec.is_target_index_exists;
begin
	if l_is_target_index_exists = true 
		and (
			i_index_rec.id is null
			or (i_index_rec.id is not null and i_index_rec.is_unique <> i_index_rec.is_target_index_unique)
		) 
	then
		execute format('
			drop index %I.%I
			'
			, i_index_rec.schema_name
			, i_index_rec.index_name
		);
		l_is_target_index_exists = false;
	end if;
	
	if i_index_rec.id is not null and l_is_target_index_exists = false then
		execute format('
			create %s index %I on %I.%I (
				%s
			)'
			, case when i_index_rec.is_unique then 'unique' else '' end
			, i_index_rec.index_name
			, i_index_rec.schema_name
			, i_index_rec.meta_type_name 
			, i_index_rec.index_columns
		);
	end if;
end
$procedure$;			
