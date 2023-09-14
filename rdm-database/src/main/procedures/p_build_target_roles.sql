create or replace procedure p_build_target_roles()
language plpgsql
as $procedure$
declare 
	l_rec record;
begin
	-- ETL user role
	if length('${etlUserRole}') > 0
		and not exists (
			select 
				1
			from 
				pg_catalog.pg_roles
      		where
      			rolname = '${etlUserRole}'
		)
  	then
  		execute 'create role ${etlUserRole}';
	end if;
	
	-- Main end user role
	if length('${mainEndUserRole}') > 0 
		and not exists (
			select 
				1
			from 
				pg_catalog.pg_roles
      		where
      			rolname = '${mainEndUserRole}'
      	) 
  	then
  		execute 'create role ${mainEndUserRole}';
	end if;

	-- Meta data views read permissions
	for l_rec in (
		select
			target_schema.nspname as view_schema
			, target_view.relname as view_name
			, user_role.name as role_name
		from 
			pg_catalog.pg_namespace target_schema
		join pg_catalog.pg_class target_view
			on target_view.relnamespace = target_schema.oid 
			and target_view.relkind in ('v'::"char", 'm'::"char")
			and target_view.relname like 'v\_meta\_%'
		join (
			values (nullif('${etlUserRole}', '')), (nullif('${mainEndUserRole}', ''))
		) as user_role(name)
			on user_role.name is not null
		left join information_schema.role_table_grants view_grant
			on view_grant.table_schema = target_schema.nspname
			and view_grant.table_name = target_view.relname
			and view_grant.grantee = user_role.name
			and view_grant.privilege_type = 'SELECT'
		where
			target_schema.nspname = '${mainSchemaName}'
			and view_grant.grantor is null
	) 
	loop
  		execute 
  			format(
  				'grant select on %I.%I to %s'
  				, l_rec.view_schema
  				, l_rec.view_name
  				, l_rec.role_name
  			)
  		;
	end loop;
end
$procedure$;	

comment on procedure p_build_target_roles(
) is 'Генерация целевых пользовательских ролей';

