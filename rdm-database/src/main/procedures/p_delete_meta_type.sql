drop procedure if exists p_delete_meta_type(
	${mainSchemaName}.meta_type.internal_name%type
	, boolean
);

create or replace procedure p_delete_meta_type(
	i_internal_name ${mainSchemaName}.meta_type.internal_name%type
	, i_skip_nonexistent boolean = false
	, i_drop_cascade boolean = false
)
language plpgsql
as $procedure$
declare 
	l_type_id ${mainSchemaName}.meta_type.id%type;
	l_schema_name ${mainSchemaName}.meta_schema.internal_name%type;
	l_log_table_name ${mainSchemaName}.meta_type.internal_name%type;
begin
	select 
		t.id
		, t.schema_name
		, t.log_table_name
	into
		l_type_id
		, l_schema_name
		, l_log_table_name
	from 
		${mainSchemaName}.v_meta_type t
	where
		t.internal_name = i_internal_name
	;

	if l_type_id is null then
		if i_skip_nonexistent then 
			return;
		else
			raise exception 'The type specified is invalid: %', i_internal_name;
		end if;
	end if;

	execute format('
		drop procedure if exists %I.p_process_%I(
			${stagingSchemaName}.data_package.id%%type
			, ${stagingSchemaName}.data_package.state_change_date%%type
		)
		'
		, l_schema_name
		, i_internal_name
	);
	
	execute format('
		drop table if exists ${stagingSchemaName}.%I
		'
		, i_internal_name
	);

	execute format('
		drop table if exists %I.%I_lc
		'
		, l_schema_name
		, i_internal_name
	);

	if l_log_table_name is not null then
		execute format('
			drop table if exists %I.%I
			'
			, l_schema_name
			, l_log_table_name
		);
	end if;

	execute format('
		drop table if exists %I.%I %s
		'
		, l_schema_name
		, i_internal_name
		, case when i_drop_cascade then 'cascade' else '' end
	);
	
	delete from ${mainSchemaName}.meta_index_column 
	where master_id in (
		select 
			i.id
		from 
			${mainSchemaName}.meta_index i
		where
			i.master_id = l_type_id
	)
	;

	delete from ${mainSchemaName}.meta_index
	where master_id = l_type_id
	;
	
	delete from ${mainSchemaName}.meta_attribute_lc 
	where master_id in (
		select 
			a.id
		from 
			${mainSchemaName}.meta_attribute a
		where
			a.master_id = l_type_id
	)
	;
	
	delete from ${mainSchemaName}.meta_attribute a
	where master_id = l_type_id
	;

	delete from ${stagingSchemaName}.data_package
	where type_id = l_type_id
	;

	delete from ${mainSchemaName}.meta_view_dependency
	where master_type_id = l_type_id
	;

	delete from ${mainSchemaName}.meta_type_lc 
	where master_id = l_type_id
	;

	delete from ${mainSchemaName}.meta_type 
	where id = l_type_id
	;
end
$procedure$;	

comment on procedure p_delete_meta_type(
	${mainSchemaName}.meta_type.internal_name%type
	, boolean
	, boolean
) is 'Удаление метатипа';
