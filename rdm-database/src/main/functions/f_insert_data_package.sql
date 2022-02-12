create or replace function ${stagingSchemaName}.f_insert_data_package(
	i_type_id ${database.defaultSchemaName}.meta_type.id%type = null
	, i_type_name ${database.defaultSchemaName}.meta_type.internal_name%type = null
	, i_source_id ${database.defaultSchemaName}.source.id%type = null
	, i_source_name ${database.defaultSchemaName}.source.internal_name%type = null
	, i_lang_id ${database.defaultSchemaName}.language.id%type = null
	, i_is_deletion bool = false
	, o_data_package_id out ${stagingSchemaName}.data_package.id%type
	, o_check_date out ${stagingSchemaName}.data_package.state_change_date%type
)
language plpgsql
as $function$
begin
	insert into 
		${stagingSchemaName}.data_package(
			type_id
			, source_id
			, lang_id
			, is_deletion
			, create_date
			, state_id
			, state_change_date
		)
	select 
		t.id
		, s.id
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
		, current_timestamp
		, (select id from ${database.defaultSchemaName}.data_package_state where internal_name = 'loaded')
		, current_timestamp
	from 
		${database.defaultSchemaName}.meta_type t
		, ${database.defaultSchemaName}.source s
	where
		(
			t.id = i_type_id
			or t.internal_name = i_type_name
		)		
		and (
			s.id = i_source_id
			or s.internal_name = i_source_name
		)		
	returning id, state_change_date into o_data_package_id, o_check_date
	;	
end
$function$;		