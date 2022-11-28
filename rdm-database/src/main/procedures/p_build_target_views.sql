create or replace procedure p_build_target_views()
language plpgsql
as $procedure$
declare 
	l_view_rec record;
	l_prev_view_id ${mainSchemaName}.meta_view.id%type;
begin
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
	
	while true
	loop
		select
			t.*
		into
			l_view_rec
		from 
			${mainSchemaName}.v_meta_view t
		join ${mainSchemaName}.meta_view meta_view 
			on meta_view.id = t.id
		where 
			(coalesce(t.is_created, false) = false or meta_view.dependency_level is null)
			and coalesce(t.is_disabled, false) = false
		order by
			t.is_external
			, t.creation_order
			, t.previously_defined_dependency_level
		limit 1
		for update of meta_view
		;
		
		if l_view_rec is null then
			exit;
		end if;
		
		if l_prev_view_id is not null then
			if l_view_rec.id = l_prev_view_id then 
				raise 'The view was not processed for a some unexpected reason: %.%...', l_view_rec.schema_name, l_view_rec.internal_name;
			end if;
		end if;
		
		l_prev_view_id = l_view_rec.id;
		
		if l_view_rec.is_external 
			and not exists (
				select 
					1
				from 
					${mainSchemaName}.meta_view_dependency dep
				join ${mainSchemaName}.meta_view v
					on v.id = dep.view_id
					and coalesce(v.is_disabled, false) = false  
				where 
					dep.view_id = l_view_rec.id
			) 
		then
			raise notice 'Disabling non-actual external view %.%...', l_view_rec.schema_name, l_view_rec.internal_name;
			
			update ${mainSchemaName}.meta_view 
			set is_disabled = true
			where id = l_view_rec.id
			;
			continue;
		end if;			

   		raise notice 'Creating view %.%...', l_view_rec.schema_name, l_view_rec.internal_name;
	
		call ${mainSchemaName}.p_build_target_view(
			i_view_rec => l_view_rec
		);
	
		-- Main end user role
		if not l_view_rec.is_external 
			and length('${mainEndUserRole}') > 0 
		then
			execute	
				format(
					'grant %s %I.%s to ${mainEndUserRole}'
					, case when l_view_rec.is_routine then 'execute on function ' else 'select on' end
					, l_view_rec.schema_name
					, l_view_rec.internal_name 
				
				);
		end if;
	end loop;
end
$procedure$;			
