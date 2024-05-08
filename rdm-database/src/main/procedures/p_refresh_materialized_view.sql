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
		case 
			when t.is_matview_emulation then
				format(
					E'do $$'
					'\nbegin'
					'\n	perform from ${mainSchemaName}.meta_view where id = %s for update;'
					'\n	call %I.p_refresh_%I();'
					'\n	update ${mainSchemaName}.meta_view set is_valid = true, refresh_time = current_timestamp where id = %s;'
					'\nend $$'
					, t.id
					, t.schema_name
					, t.internal_name
					, t.id
				)
			else 
				concat_ws(
					E';\n'
					, format(
						'select id from ${mainSchemaName}.meta_view where id = %s for update'
						, t.id
					)
					, ${mainSchemaName}.f_materialized_view_refresh_command(
						i_schema_name => t.schema_name
						, i_internal_name => t.internal_name
						, i_has_unique_index => t.has_unique_index
						, i_is_populated => t.is_populated
					)
					, format(
						'update ${mainSchemaName}.meta_view set is_valid = true, refresh_time = current_timestamp where id = %s'
						, t.id
					)
				)			
		end
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

-- Execute persmission for the ETL user role
do $$
begin
	if length('${etlUserRole}') > 0
		and not exists (
			select 
				1
			from 
				information_schema.role_routine_grants g
	  		where
	  			g.grantee = '${etlUserRole}'
	  			and g.routine_schema = '${mainSchemaName}'
	  			and g.routine_name = 'p_refresh_materialized_view'
	  			and g.privilege_type = 'EXECUTE'
		)
	then
		execute format('grant execute on procedure p_refresh_materialized_view to %s', '${etlUserRole}');
	end if;
end 
$$;

comment on procedure p_refresh_materialized_view(
	${mainSchemaName}.meta_view.id%type
) is 'Обновить материализованное представление';
