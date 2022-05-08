create or replace procedure p_delete_meta_type(
	i_internal_name ${mainSchemaName}.meta_type.internal_name%type
)
language plpgsql
as $procedure$
declare 
	l_type_id ${mainSchemaName}.meta_type.id%type;
	l_schema_name ${mainSchemaName}.meta_schema.internal_name%type;
begin
	select 
		t.id
		, coalesce(s.internal_name, '${mainSchemaName}')
	into
		l_type_id
		, l_schema_name
	from 
		${mainSchemaName}.meta_type t
	left join ${mainSchemaName}.meta_schema s
		on s.id = t.schema_id
	where
		t.internal_name = i_internal_name
	;
	
	if l_schema_name is null then
		l_schema_name := '${mainSchemaName}';
	end if;
	
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

	execute format('
		drop table if exists %I.%I
		'
		, l_schema_name
		, i_internal_name
	);
	
	if l_type_id is not null then
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
	
		delete from ${mainSchemaName}.meta_type_lc 
		where master_id = l_type_id
		;
	
		delete from ${mainSchemaName}.meta_type 
		where id = l_type_id
		;
	end if;  
end
$procedure$;			
