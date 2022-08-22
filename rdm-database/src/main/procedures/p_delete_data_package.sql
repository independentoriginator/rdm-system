create or replace procedure ${stagingSchemaName}.p_delete_data_package(
	i_data_package_id in ${stagingSchemaName}.data_package.id%type
)
language plpgsql
as $procedure$
begin
	execute 
		format('
				delete from ${stagingSchemaName}.%I
					where data_package_id = %s
			'
			, (
				select 
					t.internal_name
				from 
					${stagingSchemaName}.data_package dp
				join ${mainSchemaName}.meta_type t 
					on t.id = dp.type_id
				where
					dp.id = i_data_package_id
			)
			, i_data_package_id
		)
	;
	
	delete from 
		${stagingSchemaName}.data_package_attachment
	where
		data_package_id = i_data_package_id
	;

	delete from 
		${stagingSchemaName}.data_package
	where
		id = i_data_package_id
	;
end
$procedure$;		