create or replace procedure p_refresh_materialized_view(
	i_view_id ${mainSchemaName}.meta_view.id%type
)
language plpgsql
security definer
as $procedure$
declare 
	l_command text;
begin
	select
		format(
			'select id from ${mainSchemaName}.meta_view where id = %s for update; '
			, t.id
		)
		|| ${mainSchemaName}.f_materialized_view_refresh_command(
			i_schema_name => t.schema_name
			, i_internal_name => t.internal_name
			, i_has_unique_index => t.has_unique_index
			, i_is_populated => t.is_populated
		)
		|| format(
			'; update ${mainSchemaName}.meta_view set is_valid = true, refresh_time = current_timestamp where id = %s'
			, t.id
		)
	into 
		l_command
	from 
		${mainSchemaName}.v_meta_view t
	where 
		t.id = i_view_id
	;

	execute l_command;	
end
$procedure$;			
