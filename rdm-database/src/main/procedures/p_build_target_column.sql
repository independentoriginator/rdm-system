create or replace procedure p_build_target_column(
	i_attr_rec record
)
language plpgsql
as $procedure$
begin
	if i_attr_rec.is_staging_table_column_exists = false then 
		if i_attr_rec.is_referenced_type_temporal = true then 
			execute format('
				alter table %I.%I
					add column %I %s %snull,
					add column %I %s %snull
				'
				, i_attr_rec.staging_schema_name
				, i_attr_rec.meta_type_name 
				, i_attr_rec.internal_name 
				, i_attr_rec.target_attr_type				
				, case when i_attr_rec.is_non_nullable = true then 'not ' else '' end
				, i_attr_rec.version_ref_name
				, i_attr_rec.target_attr_type				
				, case when i_attr_rec.is_non_nullable = true then 'not ' else '' end
			);
		else
			execute format('
				alter table %I.%I
					add column %I %s %snull
				'
				, i_attr_rec.staging_schema_name
				, i_attr_rec.meta_type_name 
				, i_attr_rec.internal_name 
				, i_attr_rec.target_attr_type				
				, case when i_attr_rec.is_non_nullable = true then 'not ' else '' end
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
	
	if i_attr_rec.is_localisable = false then
		if i_attr_rec.is_column_exists = false then 
			if i_attr_rec.is_referenced_type_temporal = true then 
				execute format('
					alter table %I.%I
						add column %I %s %snull,
						add column %I %s %snull
					'
					, i_attr_rec.schema_name
					, i_attr_rec.meta_type_name 
					, i_attr_rec.internal_name 
					, i_attr_rec.target_attr_type				
					, case when i_attr_rec.is_non_nullable = true then 'not ' else '' end
					, i_attr_rec.version_ref_name
					, i_attr_rec.target_attr_type				
					, case when i_attr_rec.is_non_nullable = true then 'not ' else '' end
				);
			else
				execute format('
					alter table %I.%I
						add column %I %s %snull
					'
					, i_attr_rec.schema_name
					, i_attr_rec.meta_type_name 
					, i_attr_rec.internal_name 
					, i_attr_rec.target_attr_type				
					, case when i_attr_rec.is_non_nullable = true then 'not ' else '' end
				);
			end if;
		else
			if i_attr_rec.target_attr_type <> i_attr_rec.column_data_type then 
				execute format('
					alter table %I.%I
						alter column %I set data type %s
					'
					, i_attr_rec.schema_name
					, i_attr_rec.meta_type_name 
					, i_attr_rec.internal_name 
					, i_attr_rec.target_attr_type
				);
			end if;
		end if;
	
		if i_attr_rec.is_fk_constraint_added = true and i_attr_rec.is_fk_index_exists = false then
			if i_attr_rec.is_referenced_type_temporal = true then 
				execute format('
					create index %I on %I.%I (
						%s, %s
					)'
					, i_attr_rec.index_name
					, i_attr_rec.schema_name
					, i_attr_rec.meta_type_name 
					, i_attr_rec.internal_name
					, i_attr_rec.version_ref_name
				);
			else
				execute format('
					create index %I on %I.%I (
						%s
					)'
					, i_attr_rec.index_name
					, i_attr_rec.schema_name
					, i_attr_rec.meta_type_name 
					, i_attr_rec.internal_name
				);
			end if;
		elsif i_attr_rec.is_fk_constraint_added = false and i_attr_rec.is_fk_index_exists = true then
			execute format('
				drop index %I.%I
				'
				, i_attr_rec.schema_name
				, i_attr_rec.index_name
			);
		end if;
		
		if i_attr_rec.is_fk_constraint_added = true and i_attr_rec.is_fk_constraint_exists = false then
			if i_attr_rec.is_referenced_type_temporal = true then 
				execute format('
					alter table %I.%I
						add constraint %I foreign key (%s, %s) references %I.%I(id, version),
						add constraint %I check (case when %s is null then 1 else 0 end = case when %s is null then 1 else 0 end)
					'
					, i_attr_rec.schema_name
					, i_attr_rec.meta_type_name 
					, i_attr_rec.fk_constraint_name
					, i_attr_rec.internal_name
					, i_attr_rec.version_ref_name
					, i_attr_rec.schema_name
					, i_attr_rec.attr_type_name 
					, i_attr_rec.check_constraint_name
					, i_attr_rec.internal_name
					, i_attr_rec.version_ref_name
				);
			else				
				execute format('
					alter table %I.%I
						add constraint %I foreign key (%s) references %I.%I(id) 
					'
					, i_attr_rec.schema_name
					, i_attr_rec.meta_type_name 
					, i_attr_rec.fk_constraint_name
					, i_attr_rec.internal_name
					, i_attr_rec.schema_name
					, i_attr_rec.attr_type_name 
				);
			end if;
		elsif i_attr_rec.is_fk_constraint_added = false and i_attr_rec.is_fk_constraint_exists = true then
			execute format('
				alter table %I.%I
					drop constraint %I
				'
				, i_attr_rec.schema_name
				, i_attr_rec.meta_type_name 
				, i_attr_rec.fk_constraint_name
			);
		end if;
		
		if i_attr_rec.is_non_nullable = true and i_attr_rec.is_notnull_constraint_exists = false then
			if i_attr_rec.is_referenced_type_temporal = true then 
				execute format('
					alter table %I.%I
						alter column %s set not null,
						alter column %s set not null
					'
					, i_attr_rec.schema_name
					, i_attr_rec.meta_type_name 
					, i_attr_rec.internal_name 
					, i_attr_rec.version_ref_name
				);
			else
				execute format('
					alter table %I.%I
						alter column %s set not null
					'
					, i_attr_rec.schema_name
					, i_attr_rec.meta_type_name 
					, i_attr_rec.internal_name 
				);
			end if;				
		elsif i_attr_rec.is_non_nullable = false and i_attr_rec.is_notnull_constraint_exists = true then
			if i_attr_rec.is_referenced_type_temporal = true then
				execute format('
					alter table %I.%I
						alter column %s drop not null,
						alter column %s drop not null
					'
					, i_attr_rec.schema_name
					, i_attr_rec.meta_type_name 
					, i_attr_rec.internal_name 
					, i_attr_rec.version_ref_name						
				);
			else
				execute format('
					alter table %I.%I
						alter column %s drop not null
					'
					, i_attr_rec.schema_name
					, i_attr_rec.meta_type_name 
					, i_attr_rec.internal_name 
				);
			end if;					
		end if;
		
		if i_attr_rec.is_unique = true and i_attr_rec.is_unique_constraint_exists = false then
			execute format('
				alter table %I.%I
					add constraint %I unique (%s)
				'
				, i_attr_rec.schema_name
				, i_attr_rec.meta_type_name 
				, i_attr_rec.unique_constraint_name
				, i_attr_rec.internal_name
			);
		elsif i_attr_rec.is_unique = false and i_attr_rec.is_unique_constraint_exists = true then
			execute format('
				alter table %I.%I
					drop constraint %I
				'
				, i_attr_rec.schema_name
				, i_attr_rec.meta_type_name 
				, i_attr_rec.unique_constraint_name
			);
		end if;
		
		if i_attr_rec.default_value is not null and i_attr_rec.default_value <> coalesce(i_attr_rec.column_default, '') then
			execute format('
				alter table %I.%I
					alter column %s set default %s
				'
				, i_attr_rec.schema_name
				, i_attr_rec.meta_type_name 
				, i_attr_rec.internal_name 
				, i_attr_rec.default_value
			);
		elsif i_attr_rec.default_value is null and i_attr_rec.column_default is not null then
			execute format('
				alter table %I.%I
					alter column %s drop default
				'
				, i_attr_rec.schema_name
				, i_attr_rec.meta_type_name 
				, i_attr_rec.internal_name 
			);
		end if;
	end if;
end
$procedure$;			
