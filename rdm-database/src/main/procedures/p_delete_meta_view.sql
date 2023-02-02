drop procedure if exists p_delete_meta_view(
	${mainSchemaName}.meta_view.internal_name%type
);

drop procedure if exists p_delete_meta_view(
	${mainSchemaName}.meta_view.internal_name%type
	, boolean
);

create or replace procedure p_delete_meta_view(
	i_id ${mainSchemaName}.meta_view.id%type = null
	, i_internal_name ${mainSchemaName}.meta_view.internal_name%type = null
	, i_schema_name ${mainSchemaName}.meta_schema.internal_name%type = null
	, i_skip_nonexistent boolean = false
)
language plpgsql
as $procedure$
declare 
	l_view_id ${mainSchemaName}.v_meta_view.id%type;
	l_internal_name ${mainSchemaName}.meta_view.internal_name%type;
	l_schema_name ${mainSchemaName}.v_meta_view.schema_name%type;
	l_view_type ${mainSchemaName}.v_meta_view.view_type%type;
begin
	select 
		t.id
		, t.internal_name
		, t.schema_name
		, t.view_type
	into
		l_view_id
		, l_internal_name
		, l_schema_name
		, l_view_type
	from 
		${mainSchemaName}.v_meta_view t
	where
		(t.id = i_id or i_id is null)
		and (t.internal_name = i_internal_name or i_internal_name is null)
		and (t.schema_name = i_schema_name or i_schema_name is null)
	;

	if l_view_id is null then
		if i_skip_nonexistent then 
			return;
		else
			raise exception 'The view specified is invalid: %.% (id = %)', i_schema_name, i_internal_name, i_id;
		end if;
	end if;
	
	raise notice '%', format('
		drop %s if exists %I.%I cascade
		'
		, l_view_type
		, l_schema_name
		, l_internal_name
	);
	execute format('
		drop %s if exists %I.%I cascade
		'
		, l_view_type
		, l_schema_name
		, l_internal_name
	);
	
	delete from ${mainSchemaName}.meta_view_dependency 
	where view_id = l_view_id or master_view_id = l_view_id
	;

	delete from ${mainSchemaName}.meta_view_lc 
	where master_id = l_view_id
	;

	delete from ${mainSchemaName}.meta_view 
	where id = l_view_id
	;
end
$procedure$;			
