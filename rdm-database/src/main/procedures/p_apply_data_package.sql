create or replace procedure ${stagingSchemaName}.p_apply_data_package(
	i_data_package_id in ${stagingSchemaName}.data_package.id%type
	, i_container_name in ${database.defaultSchemaName}.meta_type.internal_name%type
	, io_check_date inout ${stagingSchemaName}.data_package.state_change_date%type
)
language plpgsql
as $procedure$
begin
	execute 
		format('
				call ${database.defaultSchemaName}.p_apply_%I(
					i_data_package_id => $1
					, io_check_date => $2
				)
			'
			, i_container_name
		)
		using 
			i_data_package_id
			, io_check_date
	;
end
$procedure$;		