create or replace procedure p_build_target_staging_table(
	i_type_rec record
)
language plpgsql
as $procedure$
begin
	if i_type_rec.is_staging_table_generated = true and i_type_rec.is_staging_table_exists = false then
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
					add column id %s null
				'
				, i_type_rec.staging_schema_name
				, i_type_rec.internal_name
				, '${type.id}'
			);
		end if;			
		
		execute format('
			create index i_%I$data_package_id on %I.%I(data_package_id);
			'
			, i_type_rec.internal_name
			, i_type_rec.staging_schema_name
			, i_type_rec.internal_name
		);
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
