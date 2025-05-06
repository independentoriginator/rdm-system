create or replace procedure 
	p_build_target_log_table_column(
		i_type_rec record
		, i_attr_rec record
	)
language plpgsql
as $procedure$
begin
	if i_type_rec.is_logged = true then
		if i_attr_rec.is_logged = true then
			if i_attr_rec.is_log_table_column_exists = false then 
				if i_attr_rec.is_referenced_type_temporal = true then 
					execute 
						format('
							alter table %I.%I
								add column %I %s null,
								add column %I %s null
							'
							, i_attr_rec.schema_name
							, i_attr_rec.log_table_name 
							, i_attr_rec.internal_name 
							, i_attr_rec.target_attr_type				
							, i_attr_rec.version_ref_name
							, i_attr_rec.target_attr_type				
						)
					;
				else
					execute
						format('
							alter table %I.%I
								add column %I %s null
							'
							, i_attr_rec.schema_name
							, i_attr_rec.log_table_name 
							, i_attr_rec.internal_name 
							, i_attr_rec.target_attr_type				
						)
					;
				end if
				;
			else
				if i_attr_rec.target_attr_type <> i_attr_rec.log_table_column_data_type then 
					execute 
						format('
							alter table %I.%I
								alter column %I set data type %s using %I::%s
							'
							, i_attr_rec.schema_name
							, i_attr_rec.log_table_name 
							, i_attr_rec.internal_name 
							, i_attr_rec.target_attr_type
							, i_attr_rec.internal_name 
							, i_attr_rec.target_attr_type
						)
					;
				end if
				;
			end if
			;
		
			if nullif(i_attr_rec.column_description, i_attr_rec.log_column_description) is not null then
				execute 
					format($$
						comment on column %I.%I.%s is $comment$%s$comment$
						$$
						, i_attr_rec.schema_name
						, i_attr_rec.log_table_name
						, i_attr_rec.internal_name		
						, i_attr_rec.column_description		
					)
				;
			
				if i_attr_rec.is_referenced_type_temporal = true then
					execute 
						format($$
							comment on column %I.%I.%s is $comment$%s$comment$
							$$
							, i_attr_rec.schema_name
							, i_attr_rec.log_table_name
							, i_attr_rec.version_ref_name				
							, i_attr_rec.column_description
						)
					;
				end if
				;	
			end if
			;
		elsif i_attr_rec.is_logged = false and i_attr_rec.is_log_table_column_exists = true then
			if i_attr_rec.is_referenced_type_temporal = true then 
				execute 
					format('
						alter table %I.%I
							drop column %I
							, drop column %I
						'
						, i_attr_rec.schema_name
						, i_attr_rec.log_table_name 
						, i_attr_rec.internal_name 
						, i_attr_rec.version_ref_name
					)
				;
			else
				execute
					format('
						alter table %I.%I
							drop column %I
						'
						, i_attr_rec.schema_name
						, i_attr_rec.log_table_name 
						, i_attr_rec.internal_name 
					)
				;
			end if
			;
		end if
		;
	end if
	;
end
$procedure$
;

comment on procedure 
	p_build_target_log_table_column(
		record
		, record
	) 
	is 'Генерация целевого столбца таблицы журнала изменений данных сущности'
;
