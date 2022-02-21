create or replace procedure ${stagingSchemaName}.p_process_data_package(
	i_data_package_id in ${stagingSchemaName}.data_package.id%type
	, i_entity_name in ${mainSchemaName}.meta_type.internal_name%type
	, io_check_date inout ${stagingSchemaName}.data_package.state_change_date%type
)
language plpgsql
as $procedure$
begin
	execute 
		format('
				call %I.p_process_%I(
					i_data_package_id => $1
					, io_check_date => $2
				)
			'
			, (select t.schema_name from ${mainSchemaName}.v_meta_type t where t.internal_name = i_entity_name)
			, i_entity_name
		)
		using 
			i_data_package_id
			, io_check_date
	;
end
$procedure$;		