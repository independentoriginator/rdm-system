create or replace procedure p_refresh_materialized_views(
	i_refresh_all boolean = false
	, i_schema_name ${mainSchemaName}.meta_schema.internal_name%type = null
)
language plpgsql
as $procedure$
declare 
	l_view_rec record;
	l_start_timestamp timestamp := clock_timestamp();
	l_timestamp timestamp;
begin
	if i_refresh_all then 
		update ${mainSchemaName}.meta_view
		set is_valid = false
		where is_valid = true;
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
			t.is_valid = false
			and (t.schema_name = i_schema_name or i_schema_name is null)
			and t.is_materialized = true
			and coalesce(meta_view.is_disabled, false) = false
		order by 
			dependency_level
		limit 1
		for update of meta_view
		;
		
		if l_view_rec is null then
			exit;
		end if;
		
   		raise notice 'Refreshing materialized view %.%...', l_view_rec.schema_name, l_view_rec.internal_name;
   		
   		l_timestamp := clock_timestamp();
   		
		execute 
			format(
				'refresh materialized view %I.%I'
				, l_view_rec.schema_name 
				, l_view_rec.internal_name
			);
			
		update ${mainSchemaName}.meta_view 
		set is_valid = true
			, refresh_time = current_timestamp
		where id = l_view_rec.id
		;
			
		commit;
		
        raise notice 'Done in %', clock_timestamp() - l_timestamp;
	end loop;
	
	raise notice 'Total time spent: %', clock_timestamp() - l_start_timestamp;
end
$procedure$;			
