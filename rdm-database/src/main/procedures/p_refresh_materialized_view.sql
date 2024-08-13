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
			E'do $$'
			'\ndeclare'
			'\n	l_start_timestamp timestamp := clock_timestamp();'
			'\nbegin'
			'\n	perform'
			'\n	from'
			'\n		${mainSchemaName}.meta_view'
			'\n	where'
			'\n		id = %s'
			'\n	for share'
			'\n	;'
			'\n	%s'
			'\n	;'
			'\n	update'
			'\n		${mainSchemaName}.meta_view'
			'\n	set'
			'\n		is_valid = true'
			'\n		, refresh_time = ${mainSchemaName}.f_current_timestamp()'
			'\n	where'
			'\n		id = %s'
			'\n	;'
			'\n	insert into'
			'\n		${stagingSchemaName}.materialized_view_refresh_duration('
			'\n			meta_view_id'
			'\n			, start_time'
			'\n			, end_time'
			'\n		)'
			'\n	values('
			'\n		%s'
			'\n		, l_start_timestamp'
			'\n		, clock_timestamp()'
			'\n	)'
			'\n	;'
			'\nend $$'
			, t.id
			, case 
				when t.is_matview_emulation then
					concat_ws(
						E'\n;'
						, format(
							'call %I.p_refresh_%I()'
							, t.schema_name
							, t.internal_name
						)
						, format(
							'analyze %I.%I'
							, t.schema_name
							, t.internal_name
						)
					)
				else
					${mainSchemaName}.f_materialized_view_refresh_command(
						i_schema_name => t.schema_name
						, i_internal_name => t.internal_name
						, i_has_unique_index => t.has_unique_index
						, i_is_populated => t.is_populated
					)
			end
			, t.id
			, t.id
		)
	into 
		l_command
	from 
		${mainSchemaName}.v_meta_view t
	where 
		t.id = i_view_id
	;

	execute 
		l_command
	;	
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
