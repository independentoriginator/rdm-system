create or replace procedure 
	p_build_target_tables()
language plpgsql
as $procedure$
declare 
	l_type_rec record
	;
begin
	call 
		${mainSchemaName}.p_build_target_roles()
	;

	call 
		${mainSchemaName}.p_build_target_schemas()
	;

	for l_type_rec in (
		select
			t.*
		from 
			${mainSchemaName}.v_meta_type t
		join ${mainSchemaName}.meta_type meta_type 
			on meta_type.id = t.id
		where 
			coalesce(t.is_built, false) = false
		order by 
			dependency_level
		for update of meta_type
	) 
	loop
		call 
			${mainSchemaName}.p_build_target_table(
				i_type_rec => l_type_rec
			)
		;
	end loop
	;

	call 
		${mainSchemaName}.p_perform_deferred_dependent_obj_rebuild()
	;

	call 
		${mainSchemaName}.p_sys_update_table_statistics(
			i_schema_name => '{${mainSchemaName}}'
			, i_max_worker_processes => 1
			, i_single_transaction => true
		)
	;
end
$procedure$
;			

comment on procedure 
	p_build_target_tables() 
	is 'Генерация целевых таблиц'
;
