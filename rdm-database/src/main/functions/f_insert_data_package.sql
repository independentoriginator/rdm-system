create or replace function ${stagingSchemaName}.f_insert_data_package(
	i_source_id ${database.defaultSchemaName}.source.id%type = null
	, i_source_name ${database.defaultSchemaName}.source.internal_name%type = null
	, i_lang_id ${database.defaultSchemaName}.language.id%type = null
	, i_is_deletion bool = false
	, i_is_partial bool = true
	, o_data_package_id out ${stagingSchemaName}.data_package.id%type
	, o_check_date out ${stagingSchemaName}.data_package.state_change_date%type
)
language plpgsql
as $function$
begin
	insert into 
		${stagingSchemaName}.data_package(
			source_id
			, lang_id
			, is_deletion
			, is_partial
			, create_date
			, state_id
			, state_change_date
		)
	select 
		s.id
		, coalesce(
			s.lang_id
			, (
				select 
					id 
				from 
					${database.defaultSchemaName}.language 
				where 
					internal_name = 'ru'
			)
		)
		, i_is_deletion
		, i_is_partial
		, current_timestamp
		, (select id from ${database.defaultSchemaName}.data_package_state where internal_name = 'created')
		, current_timestamp
	from 
		${database.defaultSchemaName}.source s
	where 
		s.id = i_source_id
		or s.internal_name = i_source_name		
	returning id, state_change_date into o_data_package_id, o_check_date
	;	
end
$function$;		