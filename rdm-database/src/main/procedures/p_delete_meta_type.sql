create or replace procedure p_delete_meta_type(
	i_internal_name ${mainSchemaName}.meta_type.internal_name%type
)
language plpgsql
as $procedure$
declare 
	l_type_id ${mainSchemaName}.meta_type.id%type;
begin
	l_type_id = (
		select 
			id
		from 
			${mainSchemaName}.meta_type 
		where 
			internal_name = i_internal_name
	);
	
	delete from ${mainSchemaName}.meta_attribute_lc 
	where attr_id in (
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

	delete from ${mainSchemaName}.meta_type_lc 
	where master_id = l_type_id
	;

	delete from ${mainSchemaName}.meta_type 
	where id = l_type_id
	;  
end
$procedure$;			
