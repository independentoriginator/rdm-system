create or replace procedure p_build_target_staging_table(
	i_type_rec record
)
language plpgsql
as $procedure$
begin
	if i_type_rec.is_staging_table_generated = true then
	
		if i_type_rec.is_staging_table_exists = false then
			execute format('
				create unlogged table %I.%I(
					data_package_id ${type.id} not null,
					constraint fk_%I$data_package_id foreign key (data_package_id) references %I.data_package(id)
				)'
				, i_type_rec.staging_schema_name
				, i_type_rec.internal_name
				, i_type_rec.internal_name
				, i_type_rec.staging_schema_name
			);
			
			if i_type_rec.is_temporal = false then
				execute format('
					alter table %I.%I
						add column id ${type.id} null
					'
					, i_type_rec.staging_schema_name
					, i_type_rec.internal_name
				);
			else
				execute format('
					alter table %I.%I
						add column id ${type.id} null
						, add column version ${type.id} null
					'
					, i_type_rec.staging_schema_name
					, i_type_rec.internal_name
				);
			end if;			
			
			execute format('
				create index i_%I$data_package_id on %I.%I(data_package_id);
				'
				, i_type_rec.internal_name
				, i_type_rec.staging_schema_name
				, i_type_rec.internal_name
			);
		end if;
		
		if i_type_rec.master_type_id is not null and i_type_rec.is_ref_to_master_column_in_staging_table_exists = false then
			if i_type_rec.is_temporal = true then 
				execute format('
					alter table %I.%I
						add column master_id %s null,
						add column master_version %s null
					'
					, i_type_rec.staging_schema_name
					, i_type_rec.internal_name 
					, '${type.id}'
					, '${type.id}'
				);
			else
				execute format('
					alter table %I.%I
						add column master_id %s null
					'
					, i_type_rec.staging_schema_name
					, i_type_rec.internal_name 
					, '${type.id}'
				);
			end if;
		end if;

		if nullif(i_type_rec.table_description, i_type_rec.staging_table_description) is not null then
			execute format($$
				comment on table %I.%I is '%s'
				$$
				, i_type_rec.staging_schema_name
				, i_type_rec.internal_name
				, i_type_rec.table_description
			);
		end if;	
		
	elsif i_type_rec.is_staging_table_generated = false and i_type_rec.is_staging_table_exists = true then
		execute format('
			drop table %I.%I
			'
			, i_type_rec.staging_schema_name
			, i_type_rec.internal_name
		);
	end if;
	
end
$procedure$;			
