create or replace function ${stagingSchemaName}.f_insert_data_package(
	i_type_id ${mainSchemaName}.meta_type.id%type = null
	, i_type_name ${mainSchemaName}.meta_type.internal_name%type = null
	, i_source_id ${mainSchemaName}.source.id%type = null
	, i_source_name ${mainSchemaName}.source.internal_name%type = null
	, i_lang_id ${mainSchemaName}.language.id%type = null
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
					l.id 
				from 
					${mainSchemaName}.language l
				where 
					l.tag = 'ru'
			)
		)
		, i_is_deletion
		, current_timestamp
		, (select ps.id from ${mainSchemaName}.data_package_state ps where ps.internal_name = 'loaded')
		, current_timestamp
	from 
		${mainSchemaName}.meta_type t
		, ${mainSchemaName}.source s
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