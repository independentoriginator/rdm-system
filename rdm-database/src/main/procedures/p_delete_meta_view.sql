create or replace procedure p_delete_meta_view(
	i_internal_name ${mainSchemaName}.meta_view.internal_name%type
)
language plpgsql
as $procedure$
declare 
	l_type_id ${mainSchemaName}.v_meta_view.id%type;
	l_schema_name ${mainSchemaName}.v_meta_view.schema_name%type;
	l_view_type ${mainSchemaName}.v_meta_view.view_type%type;
begin
	select 
		t.id
		, t.schema_name
		, t.view_type
	into
		l_type_id
		, l_schema_name
		, l_view_type
	from 
		${mainSchemaName}.v_meta_view t
	where
		t.internal_name = i_internal_name
	;
	
	execute format('
		drop %s if exists %I.%I cascade
		'
		, l_view_type
		, l_schema_name
		, i_internal_name
	);
	
	if l_type_id is not null then
		delete from ${mainSchemaName}.meta_view_lc 
		where master_id = l_type_id
		;
	
		delete from ${mainSchemaName}.meta_view 
		where id = l_type_id
		;
	end if;  
end
$procedure$;			
