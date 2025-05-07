create or replace procedure 
	p_build_target_log_table(
		i_type_rec record
	)
language plpgsql
as $procedure$
begin
	if i_type_rec.is_logged = true then
		if i_type_rec.is_log_table_exists = false then
			execute 
				format($$
					create unlogged table %I.%I(
						change_date timestamp without time zone not null
							default ${mainSchemaName}.f_current_timestamp()
						, session_context text not null 
							default 
								coalesce(
									${stagingSchemaName}.f_session_context(
										i_key => '${session_context_key_task_name}'
									)
									, session_user
								)
						, operation "char" not null
					)$$
					, i_type_rec.schema_name
					, i_type_rec.log_table_name
				)
			;
		end if
		;

		if nullif(i_type_rec.table_description, i_type_rec.log_table_description) is not null then
			execute 
				format($$
					comment on table %I.%I is $comment$%s$comment$
					$$
					, i_type_rec.schema_name
					, i_type_rec.log_table_name
					, i_type_rec.table_description
				)
			;
		end if
		;
	
		-- ETL user role read permission
		if length('${etlUserRole}') > 0 
		then
			execute	
				format(
					'grant select on %I.%s to ${etlUserRole}'
					, i_type_rec.schema_name
					, i_type_rec.log_table_name 
				
				)
			;
		end if
		;
	
	elsif i_type_rec.is_logged = false and i_type_rec.is_log_table_exists = true then
		execute 
			format('
				drop table %I.%I
				'
				, i_type_rec.schema_name
				, i_type_rec.log_table_name
			)
		;
	end if
	;
end
$procedure$
;

comment on procedure 
	p_build_target_log_table(
		record
	) 
	is 'Генерация целевой таблицы журнала изменений данных сущности'
;
