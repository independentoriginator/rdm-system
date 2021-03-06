create or replace procedure p_build_target_view(
	i_view_rec record
)
language plpgsql
as $procedure$
begin
	if i_view_rec.schema_id is not null and i_view_rec.is_schema_exists = false then
		execute format('
			create schema if not exists %I
			'
			, i_view_rec.schema_name
		);
	end if;
	
	if i_view_rec.is_view_exists then
		-- Detecting and saving dependants before cascadly dropping
		call ${mainSchemaName}.p_detect_meta_view_dependants(
			i_view_name => i_view_rec.internal_name
			, i_schema_name => i_view_rec.schema_name
			, i_is_routine => i_view_rec.is_routine
		);
	
		if i_view_rec.is_routine = false then
			execute format('
				drop %sview if exists %I.%I cascade
				'
				, case when i_view_rec.is_materialized then 'materialized ' else '' end
				, i_view_rec.schema_name
				, i_view_rec.internal_name
			);
		end if;
	end if;
	
	if i_view_rec.is_external = false or i_view_rec.is_routine = false then
		execute i_view_rec.query;
	end if;

	update ${mainSchemaName}.meta_view
	set is_created = true
		, is_valid = false
		, dependency_level = (
			select 
				${mainSchemaName}.f_meta_view_dependency_level(i_view_oid => v.view_oid)
			from 
				${mainSchemaName}.v_meta_view v
			where 
				v.id = i_view_rec.id
		)
	where 
		id = i_view_rec.id
	;
end
$procedure$;			
