create or replace procedure 
	p_build_target_index(
		i_index_rec record
	)
language plpgsql
as $procedure$
declare 
	l_is_target_index_exists bool := i_index_rec.is_target_index_exists
	;
	l_is_target_constraint_exists bool := i_index_rec.is_target_constraint_exists
	;
begin
	if l_is_target_index_exists
		and (
			i_index_rec.id is null
			or (
				i_index_rec.id is not null 
				and (
					i_index_rec.is_unique <> i_index_rec.is_target_index_unique 
					or i_index_rec.index_columns <> i_index_rec.target_index_columns
				)
			)
			or (
				i_index_rec.id is not null 
				and i_index_rec.is_unique
				and i_index_rec.is_constraint_used
			)
		) 
	then
		execute 
			format('
				drop index %I.%I
				'
				, i_index_rec.schema_name
				, i_index_rec.index_name
			)
		;
		l_is_target_index_exists = false
		;
	end if
	;

	if l_is_target_constraint_exists
		and (
			i_index_rec.id is null
			or i_index_rec.is_constraint_used = false
			or (
				i_index_rec.id is not null 
				and (
					i_index_rec.is_unique <> i_index_rec.is_target_constraint_unique 
					or i_index_rec.index_columns <> i_index_rec.target_constraint_columns
					or i_index_rec.is_constraint_deferrable <> i_index_rec.is_target_constraint_deferrable
				)
			)
		) 
	then
		execute 
			format('
				alter table %I.%I 
					drop constraint %I
				'
				, i_index_rec.schema_name
				, i_index_rec.meta_type_name 
				, i_index_rec.constraint_name
			)
		;
		l_is_target_constraint_exists = false
		;
	end if
	;

	if i_index_rec.id is not null then
		if i_index_rec.is_constraint_used and l_is_target_constraint_exists = false then
			execute 
				format('
					alter table %I.%I 
						add constraint %I %s(%s)%s
					'
					, i_index_rec.schema_name
					, i_index_rec.meta_type_name 
					, i_index_rec.constraint_name
					, case when i_index_rec.is_unique then 'unique ' else '' end
					, i_index_rec.index_columns
					, case when i_index_rec.is_constraint_deferrable then ' deferrable initially deferred' else '' end
				)
			;
		elsif l_is_target_index_exists = false then
			execute 
				format('
					create %s index %I on %I.%I (
						%s
					)'
					, case when i_index_rec.is_unique then 'unique' else '' end
					, i_index_rec.index_name
					, i_index_rec.schema_name
					, i_index_rec.meta_type_name 
					, i_index_rec.index_columns
				)
			;
		end if
		;
	end if
	;
end
$procedure$
;	

comment on procedure 
	p_build_target_index(
		record
	) 
	is 'Генерация целевого индекса'
;
