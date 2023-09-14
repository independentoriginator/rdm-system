create or replace procedure p_build_target_schemas()
language plpgsql
as $procedure$
declare 
	l_schema_rec record;
	l_role_name text;
begin
	for l_schema_rec in (
		select
			s.*
		from 
			${mainSchemaName}.v_meta_schema s
		where 
			not s.is_built
			and not s.is_external
		order by 
			s.ordinal_num
	) 
	loop
		if not l_schema_rec.is_schema_exists then
			execute format('
				create schema %I
				'
				, l_schema_rec.internal_name
			);
		end if;
	
		if nullif(l_schema_rec.schema_description, l_schema_rec.target_schema_description) is not null then
			execute format($$
				comment on schema %I is $comment$%s$comment$
				$$
				, l_schema_rec.internal_name
				, l_schema_rec.schema_description
			);
		end if;	
	
		if l_schema_rec.missed_usage_privilege_roles is not null then 
			foreach l_role_name in array l_schema_rec.missed_usage_privilege_roles loop
		  		execute 
		  			format(
		  				'grant usage on schema %I to %I'
						, l_schema_rec.internal_name
		  				, l_role_name
		  			)
		  		;
			end loop;
		end if;
	end loop;
end
$procedure$;			
