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
		execute format('
			drop %sview if exists %I.%I cascade
			'
			, case when i_view_rec.is_materialized then 'materialized ' else '' end
			, i_view_rec.schema_name
			, i_view_rec.internal_name
		);
	end if;
	
	execute i_view_rec.query;

	update ${mainSchemaName}.meta_view 
	set is_created = true
	where id = i_view_rec.id
	;
end
$procedure$;			
