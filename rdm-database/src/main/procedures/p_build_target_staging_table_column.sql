create or replace procedure p_build_target_staging_table_column(
	i_type_rec record
	, i_attr_rec record
)
language plpgsql
as $procedure$
begin
	if i_type_rec.is_staging_table_generated = true then
		if i_attr_rec.is_staging_table_column_exists = false then 
			if i_attr_rec.is_referenced_type_temporal = true then 
				execute format('
					alter table %I.%I
						add column %I %s null,
						add column %I %s null
					'
					, i_attr_rec.staging_schema_name
					, i_attr_rec.meta_type_name 
					, i_attr_rec.internal_name 
					, i_attr_rec.target_attr_type				
					, i_attr_rec.version_ref_name
					, i_attr_rec.target_attr_type				
				);
			else
				execute format('
					alter table %I.%I
						add column %I %s null
					'
					, i_attr_rec.staging_schema_name
					, i_attr_rec.meta_type_name 
					, i_attr_rec.internal_name 
					, i_attr_rec.target_attr_type				
				);
			end if;
		else
			if i_attr_rec.target_attr_type <> i_attr_rec.column_data_type then 
				execute format('
					alter table %I.%I
						alter column %I set data type %s
					'
					, i_attr_rec.staging_schema_name
					, i_attr_rec.meta_type_name 
					, i_attr_rec.internal_name 
					, i_attr_rec.target_attr_type
				);
			end if;
		end if;
	
		if i_attr_rec.is_staging_table_column_notnull_constraint_exists = true then
			if i_attr_rec.is_referenced_type_temporal = true then
				execute format('
					alter table %I.%I
						alter column %s drop not null,
						alter column %s drop not null
					'
					, i_attr_rec.staging_schema_name
					, i_attr_rec.meta_type_name 
					, i_attr_rec.internal_name 
					, i_attr_rec.version_ref_name						
				);
			else
				execute format('
					alter table %I.%I
						alter column %s drop not null
					'
					, i_attr_rec.staging_schema_name
					, i_attr_rec.meta_type_name 
					, i_attr_rec.internal_name 
				);
			end if;					
		end if;
		
		if i_attr_rec.default_value is not null and i_attr_rec.default_value <> coalesce(i_attr_rec.staging_table_column_default, '') then
			execute format('
				alter table %I.%I
					alter column %s set default %s
				'
				, i_attr_rec.staging_schema_name
				, i_attr_rec.meta_type_name 
				, i_attr_rec.internal_name 
				, i_attr_rec.default_value
			);
		elsif i_attr_rec.default_value is null and i_attr_rec.staging_table_column_default is not null then
			execute format('
				alter table %I.%I
					alter column %s drop default
				'
				, i_attr_rec.staging_schema_name
				, i_attr_rec.meta_type_name 
				, i_attr_rec.internal_name 
			);
		end if;
		
		if nullif(i_attr_rec.column_description, i_attr_rec.staging_column_description) is not null then
			execute format($$
				comment on column %I.%I.%s is '%s'
				$$
				, i_attr_rec.staging_schema_name
				, i_attr_rec.meta_type_name
				, i_attr_rec.internal_name				
				, i_attr_rec.column_description
			);
		end if;	
	end if;
end
$procedure$;			
