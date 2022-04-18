create or replace procedure p_refresh_materialized_views()
language plpgsql
as $procedure$
declare 
	l_view_rec record;
	l_start_timestamp timestamp := clock_timestamp();
	l_timestamp timestamp;
begin
	for l_view_rec in (
		select
			t.*
		from 
			${mainSchemaName}.v_meta_view t
		join ${mainSchemaName}.meta_view meta_view 
			on meta_view.id = t.id
		order by 
			dependency_level
		for update of meta_view
	) 
	loop
   		raise notice 'Refreshing materialized view %.%...', l_view_rec.schema_name, l_view_rec.internal_name;
   		l_timestamp := clock_timestamp();
		execute 
			format(
				'refresh materialized view %I.%I'
				, l_view_rec.schema_name 
				, l_view_rec.internal_name
			);
		commit;
        raise notice 'Done in %', clock_timestamp() - l_timestamp;
	end loop;
	raise notice 'Total time spent: %', clock_timestamp() - l_start_timestamp;
end
$procedure$;			
