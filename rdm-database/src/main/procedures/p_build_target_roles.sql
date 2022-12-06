create or replace procedure p_build_target_roles()
language plpgsql
as $procedure$
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
end
$procedure$;			
